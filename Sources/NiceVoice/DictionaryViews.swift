import AppKit
import SwiftUI

struct DictionaryView: View {
    var appState: AppState
    @State private var showingAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var showingImportError = false
    @State private var importErrorMessage = ""

    private let gradientColors: [Color] = [.accentColor, .accentColor]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dictionary")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("カスタム変換ルール")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Menu {
                        Button {
                            importDictionary()
                        } label: {
                            Label("インポート", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportDictionary()
                        } label: {
                            Label("エクスポート", systemImage: "square.and.arrow.up")
                        }
                        .disabled(appState.dictionaryEntries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("追加", systemImage: "plus")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(32)

            if appState.dictionaryEntries.isEmpty {
                Spacer()
                DictionaryEmptyStateView(
                    gradientColors: gradientColors,
                    onAdd: { showingAddSheet = true }
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        DictionaryTableHeader()

                        ForEach(appState.dictionaryEntries) { entry in
                            DictionaryRuleRow(
                                entry: entry,
                                onToggle: { isEnabled in
                                    var updated = entry
                                    updated.isEnabled = isEnabled
                                    appState.updateDictionaryEntry(updated)
                                },
                                onEdit: { editingEntry = entry },
                                onDelete: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        appState.removeDictionaryEntry(entry)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                }
            }

            if !appState.dictionaryEntries.isEmpty {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(appState.dictionaryEntries.count) 件のルール")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEditSheet(appState: appState, entry: nil, gradientColors: gradientColors)
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEditSheet(appState: appState, entry: entry, gradientColors: gradientColors)
        }
        .alert("インポートエラー", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "nicevoice-dictionary.json"
        panel.title = String(localized: "辞書をエクスポート")

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(appState.dictionaryEntries)
                try data.write(to: url)
                debugLog("Dictionary exported to \(url.path)")
            } catch {
                debugLog("Export failed: \(error)")
            }
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "辞書をインポート")

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let entries = try decoder.decode([DictionaryEntry].self, from: data)

                for entry in entries {
                    if !appState.dictionaryEntries.contains(where: { $0.reading == entry.reading }) {
                        appState.addDictionaryEntry(entry)
                    }
                }
                debugLog("Imported \(entries.count) dictionary entries")
            } catch {
                importErrorMessage = String(localized: "ファイルの読み込みに失敗しました: \(error.localizedDescription)")
                showingImportError = true
                debugLog("Import failed: \(error)")
            }
        }
    }
}

struct DictionaryTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("読み")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("表記")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("有効")
                .frame(width: 60, alignment: .center)
            Text("操作")
                .frame(width: 76, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DictionaryRuleRow: View {
    let entry: DictionaryEntry
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { entry.isEnabled },
            set: { onToggle($0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.reading)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.writing)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: 60)

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 1)
        }
    }
}

struct DictionaryEmptyStateView: View {
    let gradientColors: [Color]
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 8) {
                Text("辞書が空です")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("変換ルールを追加すると、\n音声認識結果に自動で適用されます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAdd) {
                Label("ルールを追加", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct DictionaryCard: View {
    let entry: DictionaryEntry
    let gradientColors: [Color]
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.reading)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))

            Text(entry.writing)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(.white.opacity(isHovered ? 0.25 : 0.15))
            )
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: isHovered ? .purple.opacity(0.4) : .purple.opacity(0.2),
                    radius: isHovered ? 12 : 6,
                    y: isHovered ? 6 : 3
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct DictionaryEditSheet: View {
    var appState: AppState
    var entry: DictionaryEntry?
    let gradientColors: [Color]
    @Environment(\.dismiss) private var dismiss
    @State private var reading = ""
    @State private var writing = ""

    private var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 24) {
            Text(isEditing ? "ルールを編集" : "ルールを追加")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("読み", systemImage: "waveform")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("例: くろーど", text: $reading)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("表記", systemImage: "character.cursor.ibeam")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("例: Claude", text: $writing)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text("キャンセル")
                        Text("esc")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                Button {
                    if let entry {
                        var updated = entry
                        updated.reading = reading
                        updated.writing = writing
                        appState.updateDictionaryEntry(updated)
                    } else {
                        let newEntry = DictionaryEntry(reading: reading, writing: writing)
                        appState.addDictionaryEntry(newEntry)
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text(isEditing ? "保存" : "追加")
                        Text("⏎")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        (reading.isEmpty || writing.isEmpty) ? Color.gray.opacity(0.55) : Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(reading.isEmpty || writing.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .onAppear {
            if let entry {
                reading = entry.reading
                writing = entry.writing
            }
        }
    }
}
