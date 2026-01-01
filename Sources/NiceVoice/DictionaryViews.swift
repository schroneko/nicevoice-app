import AppKit
import SwiftUI

struct DictionaryView: View {
    var appState: AppState
    @State private var showingAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var showingImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("辞書")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("カスタム変換ルール")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("追加", systemImage: "plus")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            if appState.dictionaryEntries.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    EmptyStateView(
                        icon: "character.book.closed",
                        title: "辞書が空です",
                        description: "変換ルールを追加すると、\n音声認識結果に自動で適用されます"
                    )
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("ルールを追加", systemImage: "plus")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            } else {
                List {
                    ForEach(appState.dictionaryEntries) { entry in
                        DictionaryEntryRow(
                            entry: entry,
                            onToggle: { enabled in
                                var updated = entry
                                updated.isEnabled = enabled
                                appState.updateDictionaryEntry(updated)
                            },
                            onEdit: { editingEntry = entry },
                            onDelete: { appState.removeDictionaryEntry(entry) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    appState.removeDictionaryEntry(entry)
                                }
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            if !appState.dictionaryEntries.isEmpty {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(appState.dictionaryEntries.count) 件のルール")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let enabledCount = appState.dictionaryEntries.filter { $0.isEnabled }.count
                    Text("\(enabledCount) 件が有効")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEditSheet(appState: appState, entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEditSheet(appState: appState, entry: entry)
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
        panel.title = "辞書をエクスポート"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(appState.dictionaryEntries)
                try data.write(to: url)
                debugLog("📤 Dictionary exported to \(url.path)")
            } catch {
                debugLog("❌ Export failed: \(error)")
            }
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "辞書をインポート"

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
                debugLog("📥 Imported \(entries.count) dictionary entries")
            } catch {
                importErrorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
                showingImportError = true
                debugLog("❌ Import failed: \(error)")
            }
        }
    }
}

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entry.isEnabled ? Color.purple.opacity(0.1) : Color.secondary.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(entry.isEnabled ? .purple : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.reading)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(entry.isEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(entry.writing)
                        .font(.caption)
                        .foregroundStyle(entry.isEnabled ? .secondary : .tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: onToggle
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct DictionaryEditSheet: View {
    var appState: AppState
    var entry: DictionaryEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var reading = ""
    @State private var writing = ""

    private var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "ルールを編集" : "ルールを追加")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("読み（認識される言葉）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例: くろーど", text: $reading)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("表記（変換後の言葉）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例: Claude", text: $writing)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "保存" : "追加") {
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
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reading.isEmpty || writing.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onAppear {
            if let entry {
                reading = entry.reading
                writing = entry.writing
            }
        }
    }
}
