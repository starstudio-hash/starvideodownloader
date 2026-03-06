//
//  UpgradePromptView.swift
//  Youtube downloader
//

import SwiftUI

// MARK: - Upgrade Reason

enum UpgradeReason {
    case dailyLimitReached
    case qualityRestricted
    case featureLocked(String)
    case batchDisabled
    case playlistDisabled

    var message: String {
        switch self {
        case .dailyLimitReached:
            return "You've reached the free daily download limit. Upgrade to Pro for unlimited downloads."
        case .qualityRestricted:
            return "4K and higher resolutions are available with a Pro license."
        case .featureLocked(let feature):
            return "\(feature) is a Pro feature. Upgrade to unlock it."
        case .batchDisabled:
            return "Batch URL input is available with a Pro license."
        case .playlistDisabled:
            return "Playlist downloading is available with a Pro license."
        }
    }
}

// MARK: - Upgrade Prompt View

struct UpgradePromptView: View {
    let reason: UpgradeReason
    @Environment(LicenseManager.self) private var license
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput: String = ""
    @State private var showKeyEntry: Bool = false
    @State private var activationError: Bool = false
    @State private var activationSuccess: Bool = false
    @State private var errorMessage: String = ""

    static let purchaseURL = URL(string: "https://firaskam.gumroad.com/l/xxmkcc")!

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "star.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            // Title
            Text("Upgrade to Pro")
                .font(.title2)
                .fontWeight(.bold)

            // Context message
            Text(reason.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            // Feature list
            VStack(alignment: .leading, spacing: 8) {
                featureRow("Unlimited downloads per day")
                featureRow("Up to 8K quality")
                featureRow("Unlimited simultaneous downloads")
                featureRow("Video processing & conversion")
                featureRow("Batch URL input & playlists")
                featureRow("SponsorBlock, subtitles & chapters")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if activationSuccess {
                // Success state
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Pro license activated!")
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            } else if showKeyEntry {
                // License key input
                VStack(spacing: 8) {
                    TextField("Enter your license key", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { attemptActivation() }
                    if activationError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack(spacing: 12) {
                        Button("Back") {
                            showKeyEntry = false
                            activationError = false
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button("Activate") { attemptActivation() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || license.isActivating)
                    }
                    if license.isActivating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } else {
                // Action buttons
                HStack(spacing: 12) {
                    Button("Enter License Key") {
                        showKeyEntry = true
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Buy Pro — $5") {
                        NSWorkspace.shared.open(Self.purchaseURL)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }

            Button("Maybe Later") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 420)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(text)
                .font(.callout)
        }
    }

    private func attemptActivation() {
        Task {
            let result = await license.activateLicense(key: keyInput)
            switch result {
            case .success:
                activationError = false
                activationSuccess = true
            case .invalidKey:
                errorMessage = license.lastError ?? "Invalid license key."
                activationError = true
            case .activationLimitReached:
                errorMessage = license.lastError ?? "Activation limit reached."
                activationError = true
            case .networkError(let msg):
                errorMessage = "Network error: \(msg)"
                activationError = true
            case .expired:
                errorMessage = license.lastError ?? "License has expired."
                activationError = true
            case .disabled:
                errorMessage = license.lastError ?? "License has been disabled."
                activationError = true
            }
        }
    }
}

// MARK: - Pro Feature Overlay

/// Overlay for locked tabs/features. Place inside a ZStack over the content.
struct ProFeatureOverlay: View {
    let featureName: String
    @Environment(LicenseManager.self) private var license
    @State private var showUpgrade = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("\(featureName) requires Pro")
                .font(.title3)
                .fontWeight(.medium)
            Button("Upgrade to Pro") {
                showUpgrade = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showUpgrade) {
            UpgradePromptView(reason: .featureLocked(featureName))
        }
    }
}
