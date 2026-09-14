// GarminAPI.swift
//
// Shared constants used across TokenProvider and GarminClient. Mirrors
// `tools/lib/garmin-auth.mjs`'s `CONNECTAPI`, `CONNECTWEB` and `UA`
// constants exactly -- the User-Agent in particular matters: Garmin's API
// has been observed to behave differently (or not at all) for requests that
// don't look like they came from the official Android app.

import Foundation

public enum GarminAPI {
    public static let connectAPI = "https://connectapi.garmin.com"
    public static let connectWeb = "https://connect.garmin.com"
}

enum GarminUserAgent {
    static let value = "com.garmin.android.apps.connectmobile"
}
