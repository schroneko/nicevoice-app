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

            Button {
                updateManager.performPrimaryAction()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: updateManager.isConfigured ? "arrow.triangle.2.circlepath.circle.fill" : "sparkles")
                    Text(updateManager.primaryActionTitle)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: updateManager.isConfigured ? [.blue, .indigo] : [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct SupportLinksContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(SupportLink.allCases.enumerated()), id: \.element.id) { index, link in
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    SettingsLinkRow(link: link)
                }
                .buttonStyle(.plain)

                if index < SupportLink.allCases.count - 1 {
                    SectionDivider()
                }
            }
        }
    }
}

struct SettingsLinkRow: View {
    let link: SupportLink
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(link.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
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
