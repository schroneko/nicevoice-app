import SwiftUI
import AVFoundation

struct HistoryItemView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .font(.caption)
                    .lineLimit(2)
                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.copyHistoryItem(record.text)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct RecentTranscriptionsCard: View {
    var appState: AppState
    @State private var hoveredId: UUID?
    @State private var showBenchmarkSheet = false
    @State private var benchmarkRecord: TranscriptionRecord?
    @State private var expectedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("最近の変換", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if !appState.history.isEmpty {
                    Text("\(appState.history.count) 件")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            if appState.history.isEmpty {
                EmptyStateView(
                    icon: "waveform.slash",
                    title: "まだ変換履歴がありません",
                    description: "fn キーを押しながら話すと、\n音声がテキストに変換されます"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.history.prefix(5).enumerated()), id: \.element.id) { index, record in
                        RecentTranscriptionRow(
                            record: record,
                            isHovered: hoveredId == record.id,
                            onCopy: { appState.copyHistoryItem(record.text) },
                            onAddToBenchmark: { rec in
                                benchmarkRecord = rec
                                expectedText = rec.text
                                showBenchmarkSheet = true
                            }
                        )
                        .onHover { isHovered in
                            hoveredId = isHovered ? record.id : nil
                        }

                        if index < min(4, appState.history.count - 1) {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .sheet(isPresented: $showBenchmarkSheet) {
            BenchmarkAddSheet(
                recognizedText: benchmarkRecord?.text ?? "",
                expectedText: $expectedText,
                onAdd: {
                    if let record = benchmarkRecord {
                        _ = appState.addToBenchmark(record, expectedText: expectedText)
                    }
                    showBenchmarkSheet = false
                },
                onCancel: {
                    showBenchmarkSheet = false
                }
            )
        }
    }
}

struct BenchmarkAddSheet: View {
    let recognizedText: String
    @Binding var expectedText: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("ベンチマークに追加")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("認識結果:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(recognizedText)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("正解テキスト:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $expectedText)
                    .frame(height: 80)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            HStack {
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("追加", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(expectedText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

struct RecentTranscriptionRow: View {
    let record: TranscriptionRecord
    let isHovered: Bool
    let onCopy: () -> Void
    var onAddToBenchmark: ((TranscriptionRecord) -> Void)? = nil
    @StateObject private var audioPlayer = AudioPlayerManager()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if record.hasAudio {
                    if let path = record.audioPath {
                        audioPlayer.toggle(url: URL(fileURLWithPath: path), id: record.id)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(record.hasAudio ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: record.hasAudio ? (audioPlayer.isPlaying ? "stop.fill" : "play.fill") : "text.bubble")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(record.hasAudio ? .blue : .secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!record.hasAudio)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .lineLimit(1)
                    .font(.callout)
                Text(record.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }

            if record.hasAudio {
                Button {
                    if let path = record.audioPath {
                        audioPlayer.toggle(url: URL(fileURLWithPath: path), id: record.id)
                    }
                } label: {
                    Label(audioPlayer.isPlaying ? "停止" : "再生", systemImage: audioPlayer.isPlaying ? "stop.fill" : "play.fill")
                }
            }

            if record.hasAudio, let onAdd = onAddToBenchmark {
                Button {
                    onAdd(record)
                } label: {
                    Label("ベンチマークに追加", systemImage: "chart.bar.doc.horizontal")
                }
            }
        }
    }
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentPlayingId: UUID?
    private var player: AVAudioPlayer?

    func play(url: URL, id: UUID) {
        stop()
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("Audio file not found: \(url.path)")
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            if player?.play() == true {
                isPlaying = true
                currentPlayingId = id
            }
        } catch {
            debugLog("Playback error: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
        currentPlayingId = nil
    }

    func toggle(url: URL, id: UUID) {
        if currentPlayingId == id && isPlaying {
            stop()
        } else {
            play(url: url, id: id)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentPlayingId = nil
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? .primary : .secondary)
            TextField("検索", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 140)
            if !text.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        }
    }
}

struct AnimatedWaveformView: View {
    @State private var animating = false
    let barCount = 5
    let barWidth: CGFloat = 2
    let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: barWidth, height: animating ? CGFloat.random(in: 4...14) : 6)
                    .animation(
                        .easeInOut(duration: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

struct ModernHistoryRowView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @ObservedObject var audioPlayer: AudioPlayerManager
    @State private var isHovered = false
    @State private var showCopiedFeedback = false
    @State private var isTapped = false

    private var isPlaying: Bool {
        audioPlayer.currentPlayingId == record.id && audioPlayer.isPlaying
    }

    private func handleAudioTap() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            isTapped = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isTapped = false
            }
        }

        guard let path = record.audioPath else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            debugLog("Audio file not found: \(path)")
            return
        }
        audioPlayer.toggle(url: url, id: record.id)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.timestamp)
    }

    private var dateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.timestamp) {
            return "今日"
        } else if calendar.isDateInYesterday(record.timestamp) {
            return "昨日"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: record.timestamp)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(isPlaying ? 0.25 : (isTapped ? 0.2 : 0.1)))
                    .frame(width: 40, height: 40)
                if isPlaying {
                    AnimatedWaveformView()
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(record.hasAudio ? .blue : .blue.opacity(0.3))
                }
            }
            .scaleEffect(isTapped ? 0.9 : 1.0)
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        handleAudioTap()
                    }
            )
            .help(record.hasAudio ? (isPlaying ? "停止" : "再生") : "音声なし")

            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if showCopiedFeedback {
                    Text("コピーしました")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }

                Button {
                    appState.copyHistoryItem(record.text)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCopiedFeedback = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopiedFeedback = false
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(isHovered ? 0.1 : 0))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appState.removeHistoryItem(record)
                    }
                } label: {
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

struct HistoryContentView: View {
    var appState: AppState
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var searchText = ""
    @State private var showingClearConfirmation = false
    @State private var animateContent = false

    private var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("履歴")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("変換した音声の記録")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SearchField(text: $searchText)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            if filteredHistory.isEmpty {
                Spacer()
                if appState.history.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "履歴がありません",
                        description: "変換した音声はここに記録されます"
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "該当する履歴がありません",
                        description: "「\(searchText)」に一致する結果が見つかりませんでした"
                    )
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredHistory) { record in
                            ModernHistoryRowView(record: record, appState: appState, audioPlayer: audioPlayer)
                                .padding(.horizontal, 20)
                                .contextMenu {
                                    Button {
                                        appState.copyHistoryItem(record.text)
                                    } label: {
                                        Label("コピー", systemImage: "doc.on.doc")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            appState.removeHistoryItem(record)
                                        }
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(appState.history.count) 件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("すべてクリア", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.history.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
                .disabled(appState.history.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .alert("履歴をすべて削除しますか？", isPresented: $showingClearConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text("この操作は取り消せません。")
        }
    }
}

struct HistoryWindowView: View {
    var appState: AppState
    @State private var searchText = ""

    private var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()

            Divider()

            if filteredHistory.isEmpty {
                Spacer()
                if appState.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("履歴がありません")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("該当する履歴がありません")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredHistory) { record in
                        HistoryRowView(record: record, appState: appState)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Text("\(appState.history.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("すべてクリア") {
                    appState.clearHistory()
                }
                .disabled(appState.history.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
}

struct HistoryRowView: View {
    let record: TranscriptionRecord
    var appState: AppState
    @State private var isHovered = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.timestamp)
    }

    private var dateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.timestamp) {
            return "今日"
        } else if calendar.isDateInYesterday(record.timestamp) {
            return "昨日"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: record.timestamp)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .lineLimit(3)
                HStack(spacing: 4) {
                    Text(dateString)
                    Text(timeString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    appState.copyHistoryItem(record.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.3)
                .help("コピー")

                Button {
                    appState.removeHistoryItem(record)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.3)
                .help("削除")
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
