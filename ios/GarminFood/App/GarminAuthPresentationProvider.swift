// GarminAuthPresentationProvider.swift
//
// `GarminAuthSession.signIn(presentationContextProvider:)` (GarminKit)
// deliberately leaves anchoring `ASWebAuthenticationSession` to the app
// target, since GarminKit itself has no UIKit dependency (see its file
// header comment). This is the standard, minimal
// `ASWebAuthenticationPresentationContextProviding` implementation: find
// the current key window across connected scenes.

import AuthenticationServices
import UIKit

final class GarminAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
