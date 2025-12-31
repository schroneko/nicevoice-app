#!/usr/bin/env swift

import Foundation
import Speech

struct TestCase: Codable {
    let id: String
    let text: String
    let audioPath: String
}

struct BenchmarkResult {
    let id: String
    let expected: String
    let actual: String
    let distance: Int
    let accuracy: Double
    let passed: Bool
}

func recognizeAudio(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")) else {
        completion(.failure(NSError(domain: "Benchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create recognizer"])))
        return
    }

    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = false

    recognizer.recognitionTask(with: request) { result, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        if let result = result, result.isFinal {
            completion(.success(result.bestTranscription.formattedString))
        }
    }
}

func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let a = Array(s1)
    let b = Array(s2)
    let m = a.count
    let n = b.count

    if m == 0 { return n }
    if n == 0 { return m }

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m { dp[i][0] = i }
    for j in 0...n { dp[0][j] = j }

    for i in 1...m {
        for j in 1...n {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
        }
    }
    return dp[m][n]
}

func normalize(_ text: String) -> String {
    text.filter { !$0.isPunctuation && !$0.isWhitespace }
}

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let manifestPath = projectRoot.appendingPathComponent("benchmark-audio/manifest.json")

print("🎯 NiceVoice ベンチマーク")
print(String(repeating: "=", count: 60))

guard FileManager.default.fileExists(atPath: manifestPath.path) else {
    print("❌ manifest.json が見つかりません")
    print("   先に generate-test-audio.mjs を実行してください")
    exit(1)
}

guard let manifestData = try? Data(contentsOf: manifestPath),
      let testCases = try? JSONDecoder().decode([TestCase].self, from: manifestData) else {
    print("❌ manifest.json の読み込みに失敗")
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

SFSpeechRecognizer.requestAuthorization { status in
    authStatus = status
    semaphore.signal()
}
semaphore.wait()

guard authStatus == .authorized else {
    print("❌ 音声認識の権限がありません")
    exit(1)
}

var results: [BenchmarkResult] = []

for testCase in testCases {
    print("\n📝 テスト: \(testCase.id)")
    print("   期待値: \(testCase.text)")

    let audioURL = projectRoot.appendingPathComponent(testCase.audioPath)
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
        print("   ❌ 音声ファイルが見つかりません")
        results.append(BenchmarkResult(id: testCase.id, expected: testCase.text, actual: "[FILE NOT FOUND]", distance: -1, accuracy: 0, passed: false))
        continue
    }

    let recognitionSemaphore = DispatchSemaphore(value: 0)
    var recognizedText: String = ""
    var recognitionError: Error?

    recognizeAudio(url: audioURL) { result in
        switch result {
        case .success(let text):
            recognizedText = text
        case .failure(let error):
            recognitionError = error
        }
        recognitionSemaphore.signal()
    }

    var waited: Double = 0
    while waited < 30 {
        if recognitionSemaphore.wait(timeout: .now() + 0.1) == .success {
            break
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        waited += 0.2
    }

    if waited >= 30 {
        print("   ❌ エラー: タイムアウト")
        results.append(BenchmarkResult(id: testCase.id, expected: testCase.text, actual: "[TIMEOUT]", distance: -1, accuracy: 0, passed: false))
        continue
    }

    if let error = recognitionError {
        print("   ❌ エラー: \(error.localizedDescription)")
        results.append(BenchmarkResult(id: testCase.id, expected: testCase.text, actual: "[ERROR]", distance: -1, accuracy: 0, passed: false))
        continue
    }

    print("   🎤 認識結果: \(recognizedText)")

    let expectedNorm = normalize(testCase.text)
    let actualNorm = normalize(recognizedText)
    let distance = levenshteinDistance(expectedNorm, actualNorm)
    let maxLen = max(expectedNorm.count, actualNorm.count)
    let accuracy = maxLen > 0 ? Double(maxLen - distance) / Double(maxLen) * 100 : 100.0
    let passed = accuracy >= 80.0

    results.append(BenchmarkResult(
        id: testCase.id,
        expected: testCase.text,
        actual: recognizedText,
        distance: distance,
        accuracy: accuracy,
        passed: passed
    ))

    let status = passed ? "✅" : "❌"
    print("   \(status) 精度: \(String(format: "%.1f", accuracy))% (編集距離: \(distance))")
}

print("\n" + String(repeating: "=", count: 60))
print("📊 結果サマリー")
print(String(repeating: "=", count: 60))

let passedCount = results.filter { $0.passed }.count
let totalCount = results.count
let validResults = results.filter { $0.distance >= 0 }
let avgAccuracy = validResults.isEmpty ? 0 : validResults.map { $0.accuracy }.reduce(0, +) / Double(validResults.count)

print("合格: \(passedCount)/\(totalCount)")
print("平均精度: \(String(format: "%.1f", avgAccuracy))%")

print("\n詳細:")
for result in results {
    let status = result.passed ? "✅" : "❌"
    print("  \(status) \(result.id): \(String(format: "%.1f", result.accuracy))%")
    if result.expected != result.actual && !result.actual.hasPrefix("[") {
        print("      期待: \(result.expected)")
        print("      実際: \(result.actual)")
    }
}

exit(passedCount == totalCount ? 0 : 1)
