import AppKit
import SwiftUI

struct EnvironmentDiagnosticsContentView: View {
    @State private var diagnostics: [DependencyDiagnostic] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(diagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                DependencyDiagnosticRowView(diagnostic: diagnostic)
                if index < diagnostics.count - 1 {
                    SectionDivider()
                }
            }

            Button {
                refresh()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("再確認")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        diagnostics = DependencyDiagnostics.snapshot()
    }
}

struct DependencyDiagnosticRowView: View {
    let diagnostic: DependencyDiagnostic
    @State private var isHovered = false

    private var badgeColor: Color {
        switch diagnostic.status {
        case .available: return .green
        case .warning: return .orange
        case .missing: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(badgeColor.opacity(0.2))
                    .overlay {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(diagnostic.title)
                            .font(.callout)
                            .fontWeight(.medium)

                        Text(diagnostic.status.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(diagnostic.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let detail = diagnostic.detail {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct UpdateSettingsContentView: View {
    @StateObject private var updateManager = AppUpdateManager.shared

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyChecksForUpdates },
            set: { updateManager.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticDownloadsBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyDownloadsUpdates },
            set: { updateManager.setAutomaticallyDownloadsUpdates($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsValueRow(
                title: "現在のバージョン",
                description: updateManager.statusDescription,
                value: "\(BundleInfo.shortVersion()) (\(BundleInfo.buildNumber()))"
            )

            if updateManager.isConfigured {
                SectionDivider()

                SettingsToggleRow(
                    title: "アップデートを自動で確認する",
                    description: "新しいリリースを定期的にチェックします",
                    isOn: automaticChecksBinding
                )

                SectionDivider()

                SettingsToggleRow(
                    title: "アップデートを自動でダウンロードする",
                    description: "見つかった更新をバックグラウンドで取得します",
                    isOn: automaticDownloadsBinding
                )
                .disabled(!updateManager.automaticallyChecksForUpdates)
            } else {
                SectionDivider()

                Text("Sparkle のフィード URL と公開鍵が未設定のため、自動更新は無効です。公開ビルドでは `NICEVOICE_APPCAST_URL` と `NICEVOICE_SPARKLE_PUBLIC_KEY` を設定してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionDivider()

            if updateManager.isConfigured {
                Button {
                    updateManager.performPrimaryAction()
                } label: {
                    Text(updateManager.primaryActionTitle)
                        .frame(minWidth: 132)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!updateManager.canPerformPrimaryAction)
            }
        }
    }
}

struct BetaAccessContentView: View {
    @State private var licenseManager = LicenseAccessManager.shared
    @State private var licenseCode = ""

    private var canSubmit: Bool {
        LicenseCode(licenseCode) != nil && licenseManager.isLicenseServerConfigured
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsValueRow(
                title: "Beta access",
                description: "ぬこスク特典のベータ機能",
                value: licenseManager.hasBetaAccess ? "有効" : "未設定"
            )

            SectionDivider()

            SettingsControlRow(title: "ライセンスコード", description: statusDescription) {
                HStack(spacing: 8) {
                    TextField("XXXX-XXXX-XXXX", text: $licenseCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                        .disabled(licenseManager.hasBetaAccess || !licenseManager.isLicenseServerConfigured)

                    Button(buttonTitle) {
                        Task {
                            await licenseManager.activate(code: licenseCode)
                            if licenseManager.hasBetaAccess {
                                licenseCode = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || licenseManager.hasBetaAccess || licenseManager.state == .activating)
                }
            }
        }
        .onAppear {
            licenseManager.reload()
        }
    }

    private var buttonTitle: String {
        licenseManager.state == .activating ? "確認中" : "適用"
    }

    private var statusDescription: String {
        switch licenseManager.state {
        case .idle:
            return "配布された個別コードを入力してください"
        case .activating:
            return "ライセンスを確認しています"
        case .activated:
            return "この Mac でベータ機能を利用できます"
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}

struct SettingsValueRow: View {
    let title: LocalizedStringKey
    let description: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
