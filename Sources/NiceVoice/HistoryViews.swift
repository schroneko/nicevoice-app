import SwiftUI
import AVFoundation

struct RecentTranscriptionsCard: View {
    var appState: AppState
    @State private var hoveredId: UUID?
    @State private var showBenchmarkSheet = false
    @State private var benchmarkRecord: TranscriptionRecord?
    @State private var expectedText = ""
    @State private var animateItems = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.2), .indigo.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    Text("最近の変換")
                        .font(.headline)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                Spacer()
                if !appState.history.isEmpty {
                    Text("\(appState.history.count) 件")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .indigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }

            if appState.history.isEmpty {
                ModernEmptyStateView(
                    icon: "waveform.slash",
                    title: "まだ変換履歴がありません",
                    description: "fn キーを押しながら話すと、\n音声がテキストに変換されます",
                    showActionButton: false
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(appState.history.prefix(5).enumerated()), id: \.element.id) { index, record in
                        ModernRecentTranscriptionRow(
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
                        .opacity(animateItems ? 1 : 0)
                        .offset(y: animateItems ? 0 : 10)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05),
                            value: animateItems
                        )
                    }
                }
                .onAppear {
                    animateItems = true
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .indigo.opacity(0.1), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .purple.opacity(0.08), radius: 20, y: 8)
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
        VStack(spacing: 24) {
            HStack {
                Text("ベンチマークに追加")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("認識結果", systemImage: "waveform")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text(recognizedText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("正解テキスト", systemImage: "text.cursor")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                TextEditor(text: $expectedText)
                    .frame(height: 80)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    }
            }

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Text("キャンセル")
                        Text("esc")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Text("追加")
                        Text("⏎")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: expectedText.isEmpty ? [.gray] : [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(expectedText.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 440)
        .background(.ultraThinMaterial)
    }
}

struct ModernRecentTranscriptionRow: View {
    let record: TranscriptionRecord
    let isHovered: Bool
    let onCopy: () -> Void
    var onAddToBenchmark: ((TranscriptionRecord) -> Void)? = nil
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if record.hasAudio {
                    if let path = record.audioPath {
                        audioPlayer.toggle(url: URL(fileURLWithPath: path), id: record.id)
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            record.hasAudio
                                ? LinearGradient(
                                    colors: [.purple.opacity(0.15), .indigo.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [.secondary.opacity(0.1), .secondary.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: record.hasAudio ? (audioPlayer.isPlaying ? "stop.fill" : "play.fill") : "text.bubble")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            record.hasAudio
                                ? LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(!record.hasAudio)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.text)
                    .lineLimit(1)
                    .font(.callout)
                Text(record.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if showCopied {
                Text("Copied")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            Button(action: {
                onCopy()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation { showCopied = false }
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(isHovered ? 0.1 : 0))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.purple.opacity(0.04) : Color.clear)
        }
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

struct ModernEmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var showActionButton: Bool = false
    var actionTitle: String = ""
    var onAction: (() -> Void)? = nil
    @State private var animateIcon = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.15), .indigo.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .blur(radius: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.1), .indigo.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(animateIcon ? 1.05 : 1.0)
                    .animation(
                        .easeInOut(duration: 2).repeatForever(autoreverses: true),
                        value: animateIcon
                    )
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            if showActionButton, let action = onAction {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text(actionTitle)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
        .onAppear {
            animateIcon = true
        }
    }
}

struct GlassmorphicSearchField: View {
    @Binding var text: String
    @State private var isFocused = false
    @FocusState private var fieldFocus: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    isFocused
                        ? LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.secondary], startPoint: .leading, endPoint: .trailing)
                )

            TextField("検索", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($fieldFocus)
                .onChange(of: fieldFocus) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFocused = newValue
                    }
                }

            if !text.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        text = ""
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 18, height: 18)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isFocused
                        ? LinearGradient(colors: [.purple.opacity(0.5), .indigo.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.secondary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
        .shadow(color: isFocused ? .purple.opacity(0.1) : .clear, radius: 8, y: 2)
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        GlassmorphicSearchField(text: $text)
            .frame(width: 180)
    }
}

struct AnimatedWaveformView: View {
    @State private var animating = false
    let barCount = 5
    let barWidth: CGFloat = 2.5
    let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isPlaying
                                ? [.purple.opacity(0.25), .indigo.opacity(0.2)]
                                : (isTapped ? [.purple.opacity(0.2), .indigo.opacity(0.15)] : [.purple.opacity(0.1), .indigo.opacity(0.08)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                if isPlaying {
                    AnimatedWaveformView()
                } else {
                    Image(systemName: record.hasAudio ? "waveform" : "text.bubble")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            record.hasAudio
                                ? LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.secondary.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
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

            VStack(alignment: .leading, spacing: 5) {
                Text(record.text)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 3, height: 3)
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if showCopiedFeedback {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Copied")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.green)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(isHovered ? 0.1 : 0))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        appState.removeHistoryItem(record)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(isHovered ? 0.08 : 0))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? Color.purple.opacity(0.03) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHovered ? Color.purple.opacity(0.1) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct HistoryContentView: View {
    var appState: AppState
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var searchText = ""
    @State private var showingClearConfirmation = false
    @State private var animateItems = false

    private var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("履歴")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("変換した音声の記録")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassmorphicSearchField(text: $searchText)
                    .frame(width: 200)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)

            if filteredHistory.isEmpty {
                Spacer()
                if appState.history.isEmpty {
                    ModernEmptyStateView(
                        icon: "clock",
                        title: "履歴がありません",
                        description: "変換した音声はここに記録されます",
                        showActionButton: true,
                        actionTitle: "音声入力を試す",
                        onAction: {
                        }
                    )
                } else {
                    ModernEmptyStateView(
                        icon: "magnifyingglass",
                        title: "該当する履歴がありません",
                        description: "「\(searchText)」に一致する結果が\n見つかりませんでした"
                    )
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, record in
                            ModernHistoryRowView(
                                record: record,
                                appState: appState,
                                audioPlayer: audioPlayer
                            )
                            .padding(.horizontal, 20)
                            .opacity(animateItems ? 1 : 0)
                            .offset(y: animateItems ? 0 : 15)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8).delay(Double(min(index, 10)) * 0.03),
                                value: animateItems
                            )
                            .contextMenu {
                                Button {
                                    appState.copyHistoryItem(record.text)
                                } label: {
                                    Label("コピー", systemImage: "doc.on.doc")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        appState.removeHistoryItem(record)
                                    }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        animateItems = true
                    }
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.1), .indigo.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    Text("\(appState.history.count) 件")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingClearConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                        Text("すべてクリア")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(appState.history.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(appState.history.isEmpty ? Color.secondary.opacity(0.05) : Color.red.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.history.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial)
        }
        .alert("履歴をすべて削除しますか？", isPresented: $showingClearConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    appState.clearHistory()
                }
            }
        } message: {
            Text("この操作は取り消せません。")
        }
    }
}

struct HistoryWindowView: View {
    var appState: AppState
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var searchText = ""
    @State private var animateItems = false

    private var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Text("履歴")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Spacer()
                }

                GlassmorphicSearchField(text: $searchText)
            }
            .padding(20)

            Divider()
                .opacity(0.5)

            if filteredHistory.isEmpty {
                Spacer()
                if appState.history.isEmpty {
                    ModernEmptyStateView(
                        icon: "clock",
                        title: "履歴がありません",
                        description: "変換した音声はここに記録されます"
                    )
                } else {
                    ModernEmptyStateView(
                        icon: "magnifyingglass",
                        title: "該当する履歴がありません",
                        description: "検索条件を変更してください"
                    )
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, record in
                            ModernHistoryRowView(record: record, appState: appState, audioPlayer: audioPlayer)
                                .padding(.horizontal, 12)
                                .opacity(animateItems ? 1 : 0)
                                .offset(y: animateItems ? 0 : 10)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.8).delay(Double(min(index, 15)) * 0.02),
                                    value: animateItems
                                )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        animateItems = true
                    }
                }
            }

            Divider()
                .opacity(0.5)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("\(appState.history.count) 件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        appState.clearHistory()
                    }
                } label: {
                    Text("すべてクリア")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(appState.history.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
                }
                .buttonStyle(.plain)
                .disabled(appState.history.isEmpty)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 420, height: 520)
        .background(.ultraThinMaterial)
    }
}
