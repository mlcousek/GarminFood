// UUIDv7.swift
//
// Event ids (add-training-checkins design D2; the architecture note's
// section 2.4): UUID version 7 (RFC 9562) -- the first 48 bits are the Unix
// time in milliseconds, so ids sort by time as strings, and the rest is
// random, so the phone (and later a watch) can make them offline without
// coordination. The vault dedupes events by this id, which is what makes a
// re-sent segment harmless.
//
// Foundation's `UUID()` is version 4 and has no v7 initialiser on this
// deployment target, so the 16 bytes are assembled here: timestamp,
// version nibble 0111, 12 random bits, variant bits 10, 62 random bits.
// Ordering WITHIN one millisecond is not guaranteed (the random bits
// decide); the per-device `seq` is what orders a device's events.
//
// Depended on by: TrainingRecorder. Tests: HubEventTests.

import Foundation

public enum UUIDv7 {
    /// A v7 UUID for `date`. `random` fills 10 bytes (injected by tests).
    public static func make(at date: Date, random: (inout [UInt8]) -> Void = UUIDv7.systemRandom) -> UUID {
        let seconds = max(0, date.timeIntervalSince1970)
        let milliseconds = UInt64((seconds * 1000).rounded(.down)) & 0xFFFF_FFFF_FFFF
        var entropy = [UInt8](repeating: 0, count: 10)
        random(&entropy)

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 {
            bytes[index] = UInt8((milliseconds >> UInt64(8 * (5 - index))) & 0xFF)
        }
        bytes[6] = 0x70 | (entropy[0] & 0x0F)
        bytes[7] = entropy[1]
        bytes[8] = 0x80 | (entropy[2] & 0x3F)
        for index in 9..<16 {
            bytes[index] = entropy[index - 6]
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// The lowercase string form the envelope carries.
    public static func string(at date: Date) -> String {
        make(at: date).uuidString.lowercased()
    }

    public static func systemRandom(_ bytes: inout [UInt8]) {
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255, using: &generator)
        }
    }

    /// The millisecond timestamp in a v7 id's first 48 bits (tests).
    static func milliseconds(of uuid: UUID) -> UInt64 {
        let u = uuid.uuid
        let head: [UInt8] = [u.0, u.1, u.2, u.3, u.4, u.5]
        return head.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
