## ADDED Requirements

### Requirement: Dates sent to and read from Garmin are Gregorian whatever the device calendar

The system SHALL write every date Garmin receives (a request path's day, a write body's date or timestamp) as a Gregorian date in a fixed POSIX format, and SHALL read Garmin's dates the same way, whatever calendar and locale the device uses. The time zone SHALL stay the one each date is defined in: the device's own for a local day or local wall-clock time, UTC for a GMT timestamp.

#### Scenario: Phone set to the Buddhist calendar
- **WHEN** the device uses the Buddhist calendar and the user logs a food on 30 September 2026
- **THEN** the entry is queued for `2026-09-30` and Today asks Garmin for `2026-09-30`, not `2569-09-30`

#### Scenario: Garmin timestamp read back on a Japanese-calendar phone
- **WHEN** a Garmin food-log timestamp `2026-09-30T00:30:00.000` is read on a device using the Japanese calendar
- **THEN** it is 00:30 on 30 September 2026 in the device's time zone

#### Scenario: Local day unchanged
- **WHEN** a food is logged at 00:30 local time
- **THEN** it belongs to that local day, as before
