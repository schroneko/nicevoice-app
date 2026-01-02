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
    @State private var pulseAnimation = false

    private let supportedTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]

    private let primaryGradient = LinearGradient(
        colors: [.purple, .indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let glassBackground = Color.white.opacity(0.08)
    private let glassBorder = Color.white.opacity(0.15)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 20) {
                        dropZone
                        youtubeInput
                    }
                    .frame(maxWidth: 380)

                    VStack(alignment: .leading, spacing: 16) {
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
            .padding(32)
        }
        .background(Color(.windowBackgroundColor))
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("バッチ文字起こし")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(primaryGradient)

            Text("音声ファイルをドラッグ＆ドロップ、または選択して文字起こし")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(primaryGradient.opacity(0.15))
                    .frame(width: 90, height: 90)
                    .scaleEffect(isDragging ? 1.1 : (pulseAnimation ? 1.02 : 1.0))

                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(primaryGradient)
                    .scaleEffect(isDragging ? 1.15 : 1.0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDragging)

            VStack(spacing: 6) {
                Text("音声ファイルをドロップ")
                    .font(.headline)
                    .foregroundStyle(isDragging ? .primary : .secondary)

                Text("mp3, m4a, wav, aiff")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("ファイルを選択")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(primaryGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(glassBackground)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isDragging ? AnyShapeStyle(primaryGradient) : AnyShapeStyle(glassBorder),
                        style: StrokeStyle(lineWidth: isDragging ? 2 : 1, dash: isDragging ? [] : [10, 6])
                    )

                if isDragging {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(primaryGradient.opacity(0.08))
                }
            }
        }
        .shadow(color: isDragging ? .purple.opacity(0.3) : .clear, radius: 20, x: 0, y: 8)
        .animation(.easeOut(duration: 0.25), value: isDragging)
        .onDrop(of: supportedTypes, isTargeted: $isDragging) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var youtubeInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("YouTube URL", systemImage: "play.rectangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("将来対応")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }

            HStack(spacing: 10) {
                TextField("https://youtube.com/...", text: $youtubeURL)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(glassBorder, lineWidth: 1)
                            }
                    }
                    .disabled(true)

                Button {
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }

            Text("YouTube からの音声抽出は今後対応予定")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(glassBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(glassBorder, lineWidth: 1)
                }
        }
        .opacity(0.7)
    }

    private var queueHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundStyle(primaryGradient)
                Text("処理キュー")
                    .font(.headline)
            }

            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(primaryGradient, in: Capsule())
            }

            Spacer()

            if !items.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        items.removeAll()
                        selectedItemId = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("すべてクリア")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                }
                .contentShape(Capsule())
            }
        }
    }

    private var queueList: some View {
        VStack(spacing: 10) {
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
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: items.count)
    }

    private var emptyQueuePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text("ファイルが追加されていません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(glassBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(glassBorder, lineWidth: 1)
                }
        }
    }

    private func resultSection(for item: BatchTranscriptionItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(primaryGradient)
                    Text(item.fileName)
                        .font(.headline)
                    Text("\(item.result.count) 文字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }

                Spacer()

                Button {
                    copyToClipboard(item.result)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("コピー")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(primaryGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(item.result)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(height: 220)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.textBackgroundColor).opacity(0.8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(glassBorder, lineWidth: 1)
                    }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(glassBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(glassBorder, lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            items.append(item)
        }
        debugLog("Added file to queue: \(url.lastPathComponent)")

        if let addedItem = items.last {
            processItem(addedItem)
        }
    }

    private func removeItem(_ item: BatchTranscriptionItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                            withAnimation(.linear(duration: 0.1)) {
                                updateItem(item.id) { $0.progress = progress }
                            }
                        }
                    },
                    onStatusChange: { _ in }
                )

                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        updateItem(item.id) {
                            $0.status = .completed
                            $0.result = result
                            $0.progress = 1.0
                        }
                        selectedItemId = item.id
                    }
                }

                await service.sendCompletionNotification(
                    fileName: item.fileName,
                    success: true,
                    charCount: result.count
                )
            } catch {
                await MainActor.run {
                    withAnimation {
                        updateItem(item.id) {
                            $0.status = .failed
                            $0.error = error.localizedDescription
                            $0.progress = 0
                        }
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

    @State private var isHovered = false

    private let primaryGradient = LinearGradient(
        colors: [.purple, .indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let successGradient = LinearGradient(
        colors: [.green, .mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let processingGradient = LinearGradient(
        colors: [.blue, .cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let errorGradient = LinearGradient(
        colors: [.red, .orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let glassBackground = Color.white.opacity(0.08)
    private let glassBorder = Color.white.opacity(0.15)

    var body: some View {
        HStack(spacing: 14) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if item.status == .processing {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(processingGradient)
                                .frame(width: geometry.size.width * item.progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                } else if let error = item.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if item.status == .completed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("\(item.result.count) 文字")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(item.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if item.status == .pending || item.status == .failed {
                    Button {
                        onProcess()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(primaryGradient, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0.7)
                }

                if item.status == .completed {
                    Button {
                        onSelect()
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(successGradient, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0.7)
                }

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)

                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(primaryGradient.opacity(0.12))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(glassBackground)
                }
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(primaryGradient.opacity(0.4), lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(glassBorder, lineWidth: 1)
            }
        }
        .shadow(color: isSelected ? .purple.opacity(0.15) : .clear, radius: 12, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
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
            Image(systemName: "clock.fill")
                .font(.system(size: 14))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.gray.opacity(0.6), .gray.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
                .tint(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(successGradient)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(errorGradient)
        }
    }
}
