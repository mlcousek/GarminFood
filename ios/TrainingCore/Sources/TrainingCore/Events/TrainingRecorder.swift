// TrainingRecorder.swift
//
// The one entry point for every training action (add-training-checkins
// design D3-D5), used by the app's Today and session detail and by the
// lock-screen Controls (through the app's TrainingEventsService):
//
//   record   validate the payload, reserve ONE sequence number from
//            VaultKit's DeviceIdentityStore (persisted before it is
//            returned, so never reused), build the envelope (UUIDv7, the
//            wall clock with its offset) and append it to the local log.
//            Durable on return; no network, ever.
//   seal     this device's unsealed events -> segment files (EventSegment),
//            each ENQUEUED in VaultKit's write queue BEFORE its events are
//            marked sealed: a crash in between can put an event in two
//            segments (the vault dedupes by id) but can never lose one.
//   drain    seal, then deliver the queue with CreateOnlyFileUploader, then
//            prune old sealed events. Auth/offline/rate limits stop the
//            cycle without spending attempts (DurableQueue's rules).
//   overlay  the log folded over the queue's state (CheckInOverlay).
//   planEdits the plan commands in the log with their status: the queue's
//            state, the projection's acks and outcomes (PendingOverlay,
//            add-plan-editing).
//
// No device id (the connection was never tested successfully) means no
// recording at all: `record` throws `.noDeviceIdentity`, and the app keeps
// the capabilities off. WHETHER to drain (connection enabled, configured,
// token, request gate) is the caller's decision; this type only drains when
// asked, and VaultPathPolicy refuses anything outside the own folder
// regardless.
//
// `CheckInPlanning` resolves which training day and session a check-in is
// for, from the cached projection only (the Controls run at 4:00, maybe
// offline).
//
// Depended on by: the app's TrainingEventsService. Tests:
// TrainingRecorderTests.

import Foundation
import VaultKit

public enum TrainingRecorderError: Error, Equatable, Sendable {
    /// The vault connection has never been tested successfully.
    case noDeviceIdentity
}

public actor TrainingRecorder {
    public let log: TrainingEventLog
    private let identity: DeviceIdentityStore
    private let queue: DurableQueue<SealedFile>
    private let makeID: @Sendable (Date) -> String

    public init(
        log: TrainingEventLog,
        identity: DeviceIdentityStore,
        queue: DurableQueue<SealedFile>,
        makeID: @escaping @Sendable (Date) -> String = { UUIDv7.string(at: $0) }
    ) {
        self.log = log
        self.identity = identity
        self.queue = queue
        self.makeID = makeID
    }

    public func hasDeviceIdentity() async -> Bool {
        await identity.currentID() != nil
    }

    /// See this file's header. Durable on return.
    @discardableResult
    public func record(_ payload: HubEventPayload, now: Date = Date(), timeZone: TimeZone = .current) async throws -> HubEvent {
        try payload.validate()
        guard let deviceID = await identity.currentID() else {
            throw TrainingRecorderError.noDeviceIdentity
        }
        let seq = try await identity.reserveSequence(count: 1).lowerBound
        let event = HubEvent(
            id: makeID(now),
            deviceId: deviceID.rawValue,
            seq: seq,
            at: HubEventClock.string(now, timeZone: timeZone),
            payload: payload
        )
        try await log.append(event, now: now)
        return event
    }

    /// Seals this device's unsent events; returns how many segments were
    /// queued.
    @discardableResult
    public func seal(now: Date = Date()) async throws -> Int {
        guard let deviceID = await identity.currentID() else { return 0 }
        let pending = await log.unsealed()
            .filter { $0.event.deviceId == deviceID.rawValue }
            .map(\.event)
            .sorted { $0.seq < $1.seq }
        let chunks = EventSegment.chunks(pending)
        for chunk in chunks {
            let file = try EventSegment.seal(chunk, deviceID: deviceID, sealedAt: now)
            try await queue.enqueue(file, now: now)
            try await log.markSealed(chunk.map(\.id), segment: file.id)
        }
        return chunks.count
    }

    /// Seal, deliver, prune. The caller decides whether the connection
    /// allows it.
    @discardableResult
    public func drain(transport: VaultTransport, now: Date = Date()) async -> DurableQueueDrainResult {
        do {
            try await seal(now: now)
        } catch {
            VaultLog.log(.warning, "training events: sealing failed (\(type(of: error))); events stay on the phone")
        }
        let result = await queue.drain(using: CreateOnlyFileUploader(transport: transport), now: now)
        do {
            try await log.prune(now: now)
        } catch {
            VaultLog.log(.warning, "training events: pruning failed (\(type(of: error)))")
        }
        return result
    }

    /// The phone's events as the screens show them; `acks` is the cached
    /// projection's `acks` (empty until the vault has read any).
    public func overlay(acks: [String: JSONValue] = [:]) async -> CheckInOverlay {
        let events = await log.all()
        let unsent = Set(await queue.all().filter { $0.state != .sent }.map { $0.record.id })
        return CheckInOverlay.fold(events, unsentSegments: unsent, ackedSeqs: CheckInOverlay.ackedSeqs(from: acks))
    }

    /// The phone's plan commands and what became of them (add-plan-editing
    /// D4); `acks` and `outcomes` are the cached projection's.
    public func planEdits(acks: [String: JSONValue] = [:], outcomes: [JSONValue] = []) async -> PendingOverlay {
        let events = await log.all()
        let unsent = Set(await queue.all().filter { $0.state != .sent }.map { $0.record.id })
        return PendingOverlay.fold(
            events,
            unsentSegments: unsent,
            ackedSeqs: CheckInOverlay.ackedSeqs(from: acks),
            outcomes: PlanOutcome.parse(outcomes)
        )
    }

    /// Events not yet uploaded: unsealed ones, plus those in segments still
    /// pending or failed.
    public func waitingCount() async -> Int {
        let events = await log.all()
        let unsent = Set(await queue.all().filter { $0.state != .sent }.map { $0.record.id })
        return events.filter { logged in
            guard let segment = logged.segmentID else { return true }
            return unsent.contains(segment)
        }.count
    }
}

// MARK: - Which day and session a check-in is for

public enum CheckInPlanning {
    /// The training day "now" is on, in the plan's zone and day boundary
    /// (the device's zone when the plan has none).
    public static func trainingDay(now: Date, athlete: Athlete, deviceTimeZone: TimeZone) -> LocalDate {
        TrainingDay.current(now: now, boundaryHour: athlete.dayBoundaryHour, timeZone: athlete.timeZone(fallback: deviceTimeZone))
    }

    /// The day's traffic-light session: the first with options, else the
    /// first marked `trafficLight`; `nil` on a rest day.
    public static func checkInSessionID(on date: LocalDate, plan: Plan?) -> String? {
        guard let plan, let day = EffectivePlan(plan: plan).day(date) else { return nil }
        if let session = day.sessions.first(where: { !$0.options.isEmpty }) { return session.id }
        return day.sessions.first(where: { $0.trafficLight })?.id
    }

    /// The check-in the Controls record: today's training day, its session.
    public static func morningCheckIn(light: MorningLight, projection: Projection?, now: Date, deviceTimeZone: TimeZone) -> MorningCheckInPayload {
        let athlete = projection?.athlete ?? Athlete()
        let date = trainingDay(now: now, athlete: athlete, deviceTimeZone: deviceTimeZone)
        return MorningCheckInPayload(date: date, light: light, sessionId: checkInSessionID(on: date, plan: projection?.plan))
    }
}
