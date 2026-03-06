//
//  LicenseManager.swift
//  Youtube downloader
//

import Foundation

@Observable
class LicenseManager {

    // MARK: - Types

    enum LicenseTier {
        case free
        case pro
    }

    enum ActivationResult {
        case success
        case invalidKey
        case activationLimitReached
        case networkError(String)
        case expired
        case disabled
    }

    // MARK: - Constants

    static let freeDailyDownloadLimit: Int = 5
    static let freeMaxConcurrentDownloads: Int = 1

    /// Gumroad product permalink
    static let gumroadProductID: String = "xxmkcc"

    // MARK: - Persisted State

    var licenseKey: String = ""
    var instanceID: String = ""
    var activationDate: Date? = nil
    var dailyDownloadCount: Int = 0
    var lastDownloadDate: Date? = nil

    /// True while an activation/validation request is in progress
    var isActivating: Bool = false
    var lastError: String? = nil

    // MARK: - Computed Properties

    var currentTier: LicenseTier {
        if !licenseKey.isEmpty && !instanceID.isEmpty {
            return .pro
        }
        return .free
    }

    var isPro: Bool { currentTier == .pro }

    /// True if user has full features (Pro license active)
    var hasFullAccess: Bool {
        isPro
    }

    var canDownload: Bool {
        if hasFullAccess { return true }
        resetDailyCountIfNeeded()
        return dailyDownloadCount < Self.freeDailyDownloadLimit
    }

    var dailyDownloadsRemaining: Int {
        if hasFullAccess { return Int.max }
        resetDailyCountIfNeeded()
        return max(0, Self.freeDailyDownloadLimit - dailyDownloadCount)
    }

    /// The effective maximum concurrent downloads based on license
    /// Pro users get unlimited (capped at a practical maximum of 99)
    var effectiveMaxConcurrentDownloads: Int {
        hasFullAccess ? 99 : Self.freeMaxConcurrentDownloads
    }

    /// Quality options available for the current tier
    var allowedQualities: [VideoQuality] {
        if hasFullAccess {
            return VideoQuality.allCases
        }
        // Free tier: up to 1080p + audio only
        return VideoQuality.allCases.filter { quality in
            switch quality {
            case .best4k, .best2k, .best:
                return false
            default:
                return true
            }
        }
    }

    /// Whether a quality option requires Pro
    func isProOnly(_ quality: VideoQuality) -> Bool {
        switch quality {
        case .best4k, .best2k, .best:
            return true
        default:
            return false
        }
    }

    // MARK: - Persistence Keys

    private enum Keys {
        static let licenseKey = "license_key"
        static let instanceID = "license_instanceID"
        static let activationDate = "license_activationDate"
        static let dailyDownloadCount = "license_dailyDownloadCount"
        static let lastDownloadDate = "license_lastDownloadDate"
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        licenseKey = d.string(forKey: Keys.licenseKey) ?? ""
        instanceID = d.string(forKey: Keys.instanceID) ?? ""
        activationDate = d.object(forKey: Keys.activationDate) as? Date
        dailyDownloadCount = d.integer(forKey: Keys.dailyDownloadCount)
        lastDownloadDate = d.object(forKey: Keys.lastDownloadDate) as? Date
    }

    // MARK: - Gumroad License Activation

    /// Activate a license key via Gumroad's API
    func activateLicense(key: String) async -> ActivationResult {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return .invalidKey }

        isActivating = true
        lastError = nil
        defer { isActivating = false }

        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            return .networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "product_id=\(Self.gumroadProductID)&license_key=\(trimmedKey)&increment_uses_count=true"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError("Invalid response")
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let success = json["success"] as? Bool ?? false

            if httpResponse.statusCode == 200 && success {
                // Verify it's for the right product
                if let purchase = json["purchase"] as? [String: Any] {
                    let productPermalink = purchase["product_permalink"] as? String ?? ""
                    if !productPermalink.isEmpty && !productPermalink.contains(Self.gumroadProductID) {
                        lastError = "License key is not for this product."
                        return .invalidKey
                    }
                }

                licenseKey = trimmedKey
                instanceID = trimmedKey // Gumroad uses the key itself as the identifier
                activationDate = Date()
                save()
                return .success

            } else {
                let message = json["message"] as? String ?? ""

                if httpResponse.statusCode == 404 || message.lowercased().contains("not found") {
                    lastError = "License key not found."
                    return .invalidKey
                }

                if message.lowercased().contains("limit") || message.lowercased().contains("uses") {
                    lastError = "This license key has already been used on too many devices."
                    return .activationLimitReached
                }

                lastError = message.isEmpty ? "Invalid license key." : message
                return .invalidKey
            }
        } catch {
            lastError = "Network error: \(error.localizedDescription)"
            return .networkError(error.localizedDescription)
        }
    }

    /// Deactivate (clear) the current license locally
    func deactivateLicense() async {
        licenseKey = ""
        instanceID = ""
        activationDate = nil
        save()
    }

    /// Validate the current license is still valid via Gumroad's API
    func validateLicense() async -> Bool {
        guard !licenseKey.isEmpty else { return false }

        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "product_id=\(Self.gumroadProductID)&license_key=\(licenseKey)&increment_uses_count=false"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let success = json["success"] as? Bool ?? false

            if success {
                return true
            } else {
                // License is no longer valid — clear it
                licenseKey = ""
                instanceID = ""
                activationDate = nil
                save()
                return false
            }
        } catch {
            // Network error — don't revoke, just return current state
            return isPro
        }
    }

    // MARK: - Download Tracking

    /// Call this when a download starts to increment the daily counter
    func recordDownload() {
        resetDailyCountIfNeeded()
        dailyDownloadCount += 1
        lastDownloadDate = Date()
        save()
    }

    private func resetDailyCountIfNeeded() {
        guard let lastDate = lastDownloadDate else { return }
        if !Calendar.current.isDateInToday(lastDate) {
            dailyDownloadCount = 0
        }
    }

    // MARK: - Persistence

    func save() {
        let d = UserDefaults.standard
        d.set(licenseKey, forKey: Keys.licenseKey)
        d.set(instanceID, forKey: Keys.instanceID)
        d.set(activationDate, forKey: Keys.activationDate)
        d.set(dailyDownloadCount, forKey: Keys.dailyDownloadCount)
        d.set(lastDownloadDate, forKey: Keys.lastDownloadDate)
    }
}
