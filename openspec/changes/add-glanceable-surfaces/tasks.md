## 17. Controls (the primary lock-screen/Action-Button surface)

- [ ] 17.1 Build a `ControlWidgetButton` per quick-pick food (from `add-food-log-core`'s local ranking), each with its own `AppIntent` carrying `authenticationPolicy = .alwaysAllowed` and `supportedModes = [.background]`.
- [ ] 17.2 Verify a Control fires while the device is locked, with no Face ID prompt, and confirm the entry lands in that process's local outbox (per `garmin-sync`).
- [ ] 17.3 Add `controlWidgetStatus` feedback ("Logged 250 kcal") and `controlWidgetActionHint` text.
- [ ] 17.4 Place the primary quick-pick Control on the Action Button (iPhone 15 Pro+) and document that this specific placement is hardware-dependent, not a baseline requirement.
- [ ] 17.5 Build the barcode-scan Control (`OpenIntent`, target membership spanning app + extension) that opens the app directly into the scanner from `add-food-log-core`.

## 18. Lock Screen accessory (read-only)

- [ ] 18.1 Build the `accessoryCircular`/`accessoryRectangular` ring showing today's total, read fresh from Garmin's daily-summary route.
- [ ] 18.2 Confirm no interactive element is placed here — verify the family renders in `vibrant`/`accented` mode correctly with no `fullColor` assets.

## 19. Home Screen widget

- [ ] 19.1 Build the `systemSmall` widget: `Gauge`-based ring plus 2-4 `Button(intent:)` quick-add tiles bound to the same quick-pick foods as the Controls.
- [ ] 19.2 Implement the `TimelineProvider` reading the daily-summary route with a short cache, per design.md D2 — never a locally-aggregated total.
- [ ] 19.3 Show locally-pending (not-yet-reconciled) entries as a visually distinct provisional addition on top of the last confirmed Garmin total.
- [ ] 19.4 Verify a same-widget quick-add tap updates the ring instantly via the guaranteed free post-intent reload, without consuming reload budget.
- [ ] 19.5 Set the widget's local store's file protection to `NSFileProtectionCompleteUntilFirstUserAuthentication` and verify the widget still appears on the Mac via Continuity.

## 20. Siri and Shortcuts

- [ ] 20.1 Implement `AppShortcutsProvider` with 3 shortcuts: log the top quick-pick food, log a named food (parameterised), open the scanner. Confirm each phrase includes `\(.applicationName)`.
- [ ] 20.2 Donate each completed log via `IntentDonationManager`, and delete the donation when an entry is deleted.
- [ ] 20.3 Verify via Xcode's App Shortcuts Preview that all phrases resolve correctly and the app stays well under the 10-shortcut cap.

## 21. Cross-surface verification

- [ ] 21.1 Log once from each surface (app, Control, widget quick-add, Siri) in one sitting and confirm all four entries reconcile correctly in Garmin with no duplicates.
- [ ] 21.2 Verify the expired-token state (`add-garmin-auth-and-sync` D7) surfaces correctly on the widget and Control, not just in the app.
- [ ] 21.3 Time the fastest path (Action Button hold-to-log) end to end and confirm it is genuinely at or under two user actions.
