import SwiftUI
import UniformTypeIdentifiers

struct BatchTranscriptionView: View {
    var appState: AppState
    @State private var items: [BatchTranscriptionItem] = []
    @State private var isProcessing = false
    @State private var isDragging = false
    @State private var youtubeURL = ""
    @State private var showFileImporter = false
    @State private var selectedItemId: UUID?

    private let supportedTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        dropZone
                        youtubeInput
                    }
                    .frame(maxWidth: 360)

                    VStack(alignment: .leading, spacing: 12) {
                        queueHeader
                        queueList
                    }
                    .frame(maxWidth: .infinity)
                }

                if let selectedItem = items.first(where: { $0.id == selectedItemId }),
                   !selectedItem.result.isEmpty {
                    resultSection(for: selectedItem)
                }

                Spacer()
            }
            .padding(28)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("バッチ文字起こし")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("音声ファイルをドラッグ＆ドロップ、または選択して文字起こし")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(isDragging ? .blue : .secondary)

            Text("音声ファイルをドロップ")
                .font(.headline)
                .foregroundStyle(isDragging ? .blue : .primary)

            Text("mp3, m4a, wav, aiff")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("ファイルを選択") {
                showFileImporter = true
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDragging ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isDragging ? Color.blue : Color.gray.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                        )
                }
        }
        .onDrop(of: supportedTypes, isTargeted: $isDragging) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var youtubeInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("YouTube URL（将来対応）", systemImage: "play.rectangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField("https://youtube.com/...", text: $youtubeURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button {
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .disabled(true)
            }

            Text("YouTube からの音声抽出は今後対応予定")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.controlBackgroundColor))
        }
        .opacity(0.6)
    }

    private var queueHeader: some View {
        HStack {
            Text("処理キュー")
                .font(.headline)

            Spacer()

            if !items.isEmpty {
                Button("すべてクリア") {
                    withAnimation {
                        items.removeAll()
                        selectedItemId = nil
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var queueList: some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                emptyQueuePlaceholder
            } else {
                ForEach(items) { item in
                    QueueItemRow(
                        item: item,
                        isSelected: selectedItemId == item.id,
                        onSelect: { selectedItemId = item.id },
                        onRemove: { removeItem(item) },
                        onProcess: { processItem(item) }
                    )
                }
            }
        }
    }

    private var emptyQueuePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("ファイルが追加されていません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.controlBackgroundColor).opacity(0.5))
        }
    }

    private func resultSection(for item: BatchTranscriptionItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("結果: \(item.fileName)", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                Button {
                    copyToClipboard(item.result)
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(item.result)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(height: 200)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.textBackgroundColor))
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.controlBackgroundColor))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else {
                        if let error = error {
                            debugLog("Drop error: \(error)")
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.addFile(url)
                    }
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                addFile(url)
            }
        case .failure(let error):
            debugLog("File import error: \(error)")
        }
    }

    private func addFile(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }

        var item = BatchTranscriptionItem(url: url)
        items.append(item)
        debugLog("Added file to queue: \(url.lastPathComponent)")

        if let addedItem = items.last {
            processItem(addedItem)
        }
    }

    private func removeItem(_ item: BatchTranscriptionItem) {
        withAnimation {
            items.removeAll { $0.id == item.id }
            if selectedItemId == item.id {
                selectedItemId = nil
            }
        }
    }

    private func processItem(_ item: BatchTranscriptionItem) {
        guard #available(macOS 26.0, *) else {
            updateItem(item.id) { $0.status = .failed; $0.error = "macOS 26.0 以上が必要です" }
            return
        }

        guard item.status == .pending || item.status == .failed else { return }

        updateItem(item.id) {
            $0.status = .processing
            $0.progress = 0
            $0.error = nil
        }

        Task {
            let service = BatchTranscriptionService.shared
            await service.requestNotificationPermission()

            do {
                let result = try await service.transcribeFile(
                    at: item.url,
                    onProgress: { progress in
                        DispatchQueue.main.async {
                            updateItem(item.id) { $0.progress = progress }
                        }
                    },
                    onStatusChange: { _ in }
                )

                await MainActor.run {
                    updateItem(item.id) {
                        $0.status = .completed
                        $0.result = result
                        $0.progress = 1.0
                    }
                    selectedItemId = item.id
                }

                await service.sendCompletionNotification(
                    fileName: item.fileName,
                    success: true,
                    charCount: result.count
                )
            } catch {
                await MainActor.run {
                    updateItem(item.id) {
                        $0.status = .failed
                        $0.error = error.localizedDescription
                        $0.progress = 0
                    }
                }

                await service.sendCompletionNotification(
                    fileName: item.fileName,
                    success: false
                )
            }
        }
    }

    private func updateItem(_ id: UUID, update: (inout BatchTranscriptionItem) -> Void) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            update(&items[index])
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("Copied result to clipboard: \(text.count) chars")
    }
}

struct QueueItemRow: View {
    let item: BatchTranscriptionItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onProcess: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if item.status == .processing {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                } else if let error = item.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if item.status == .completed {
                    Text("\(item.result.count) 文字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if item.status == .pending || item.status == .failed {
                    Button {
                        onProcess()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                }

                if item.status == .completed {
                    Button {
                        onSelect()
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.status == .completed {
                onSelect()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
