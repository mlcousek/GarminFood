// VaultErrorPresentation.swift
//
// Every typed vault outcome, banner reason and input problem, as localized
// text (add-vault-connection task 4.3). VaultKit has no user-facing strings
// by design (D1): it returns typed values, and this is the one place they
// become English or Czech -- so the wording can change without touching the
// package, and the localization checker sees every key in the app catalog.
// Counts use plural catalog entries ("Expires in %lld days"), never a
// ternary. DiagnosticsLog lines stay English and are written in VaultKit.
//
// Depended on by: VaultBannerView, VaultSettingsView.

import Foundation
import VaultKit

enum VaultErrorPresentation {
    // MARK: - Banner (design D10)

    static func bannerTitle(_ reason: VaultBannerReason) -> String {
        switch reason {
        case .authProblem(let problem):
            return authProblem(problem)
        case .tokenMissing:
            return String(localized: "Paste your vault token again")
        case .tokenExpiring(let days):
            if days <= 0 {
                return String(localized: "Vault token expires today")
            }
            return String(localized: "Vault token expires in \(days) days")
        }
    }

    static func authProblem(_ problem: VaultAuthProblem) -> String {
        switch problem {
        case .tokenRejected:
            return String(localized: "Vault token expired or revoked")
        case .forbidden:
            return String(localized: "The token can't access this repository")
        case .repositoryNotFound:
            return String(localized: "Repository not found, or the token can't see it")
        }
    }

    // MARK: - Outcomes (design D6)

    static func outcome(_ outcome: VaultOutcome) -> String {
        switch outcome {
        case .success, .alreadyExists:
            return String(localized: "Connected")
        case .authFailed(let problem):
            return authProblem(problem)
        case .fileNotFound:
            return String(localized: "Connected. No plan data yet.")
        case .rateLimited:
            return String(localized: "GitHub asked to slow down. The app will try again later.")
        case .conflict:
            return String(localized: "GitHub reported a conflict. The app will try again later.")
        case .serverError(let status):
            return String(localized: "GitHub had a problem (\(status)). The app will try again later.")
        case .offline:
            return String(localized: "Offline. The last plan stays available.")
        case .refusedByPolicy:
            return String(localized: "Blocked by the app's own path rules.")
        case .redirectRefused:
            return String(localized: "GitHub redirected somewhere else, so the request was stopped.")
        case .notConfigured:
            return String(localized: "Enter the repository and a token first.")
        case .unexpected(let status):
            return String(localized: "Unexpected answer from GitHub (\(status)).")
        case .transportError:
            return String(localized: "Couldn't reach GitHub.")
        }
    }

    // MARK: - Expiry (design D10)

    /// "Expires in N days", "Expires today" or "Expiry unknown".
    static func expiry(days: Int?) -> String {
        guard let days else { return String(localized: "Expiry unknown") }
        if days <= 0 { return String(localized: "Expires today") }
        return String(localized: "Expires in \(days) days")
    }

    // MARK: - Input problems

    static func tokenProblem(_ problem: VaultTokenProblem) -> String {
        switch problem {
        case .empty:
            return String(localized: "Paste a token first.")
        case .classicToken, .notFineGrained:
            return String(localized: "Use a fine-grained token limited to one repository.")
        case .malformed:
            return String(localized: "That doesn't look like a complete GitHub token.")
        }
    }

    static func tokenSaveError(_ error: VaultController.TokenSaveError) -> String {
        switch error {
        case .invalid(let problem):
            return tokenProblem(problem)
        case .keychain:
            return String(localized: "Couldn't save the token to the Keychain. Try again.")
        }
    }

    static func repositoryProblem(_ problem: VaultRepositoryProblem) -> String {
        switch problem {
        case .invalidOwner:
            return String(localized: "Check the owner: letters, digits and hyphens only.")
        case .invalidName:
            return String(localized: "Check the repository name: letters, digits, dots, hyphens and underscores only.")
        case .invalidBranch:
            return String(localized: "Check the branch name.")
        }
    }
}
