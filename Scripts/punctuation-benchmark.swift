#!/usr/bin/env swift

import Foundation

struct PunctuationTestCase: Codable {
    let id: String
    let input: String
    let expected: String
    let description: String
}

struct TestResult {
    let id: String
    let input: String
    let expected: String
    let actual: String
    let passed: Bool
}

func removeLeadingFillers(_ text: String) -> String {
    var result = text
    let headFillers = ["あの", "えっと", "えーと"]
    let contextFillers = ["あの", "えっと", "えーと"]

    for filler in headFillers {
        if result.hasPrefix(filler) {
            result = String(result.dropFirst(filler.count))
        }
    }

    for filler in contextFillers {
        result = result.replacingOccurrences(of: "、\(filler)", with: "、")
        result = result.replacingOccurrences(of: "。\(filler)", with: "。")
        result = result.replacingOccurrences(of: "に\(filler)", with: "に")
        result = result.replacingOccurrences(of: "もう\(filler)", with: "もう")
    }

    let fillerPronounPatterns = [
        "あの私", "あの僕", "あの俺", "あの彼", "あの彼女", "あのあなた", "あの君",
        "その私", "その僕", "その俺", "その彼", "その彼女", "そのあなた", "その君"
    ]
    for pattern in fillerPronounPatterns {
        let pronoun = String(pattern.dropFirst(2))
        result = result.replacingOccurrences(of: pattern, with: pronoun)
    }

    return result
}

func removePunctuationBeforeFinalParticles(_ text: String) -> String {
    var result = text
    for particle in ["ね", "よ"] {
        for separator in ["、", "。"] {
            for pattern in ["\(separator)\(particle)。", "\(separator)\(particle)？", "\(separator)\(particle)！"] {
                result = result.replacingOccurrences(of: pattern, with: "\(particle)\(String(pattern.last!))")
            }
            if result.hasSuffix("\(separator)\(particle)") {
                result = String(result.dropLast(2)) + particle
            }
        }
    }
    return result
}

func addLocalPunctuation(_ text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.isEmpty else { return result }

    let headFillers = ["あの", "えっと", "えーと"]
    for filler in headFillers {
        if result.hasPrefix(filler) {
            result = String(result.dropFirst(filler.count))
        }
    }

    let punctuations = ["。", "、", "？", "！", "?", "!", ".", ","]
    for punct in punctuations {
        result = result.replacingOccurrences(of: " \(punct)", with: punct)
        result = result.replacingOccurrences(of: "　\(punct)", with: punct)
    }

    let builtInDictionary = [
        ("クロードコード", "Claude Code"),
        ("クロードエムディー", "CLAUDE.md"),
        ("ラングラー", "Wrangler"),
        ("クロード", "Claude"),
        ("スーパーベース", "Supabase"),
        ("スパベース", "Supabase"),
        ("グロック", "Grok"),
        ("ジェイソン", "JSON"),
        ("チャットGPT", "ChatGPT"),
        ("ウルトラシンク", "ultrathink"),
        ("シェモア", "chezmoi"),
        ("でぃすこーど", "Discord"),
        ("ワンパスワード", "1Password"),
    ]
    for (reading, writing) in builtInDictionary {
        result = result.replacingOccurrences(of: reading, with: writing)
    }

    let midSentenceBreakers = [
        "ありがとうございます", "すみません",
        "こんにちは", "こんばんは", "おはようございます", "お疲れ様です", "お疲れさまです"
    ]

    let sentenceEndings = ["ました", "ません", "でした"]
    for ending in sentenceEndings {
        var searchStart = result.startIndex
        while let range = result.range(of: ending, range: searchStart..<result.endIndex) {
            let afterEnd = range.upperBound
            if afterEnd < result.endIndex {
                let nextChar = result[afterEnd]
                let isNextPunctuation = nextChar == "。" || nextChar == "、" || nextChar == "？" || nextChar == "！" || nextChar == "か" || nextChar == "が" || nextChar == "け" || nextChar == "ね" || nextChar == "よ"
                let suffixAfter = String(result[afterEnd...])
                let isContinuation = suffixAfter.hasPrefix("でした") || suffixAfter.hasPrefix("っけ") || suffixAfter.hasPrefix("よね") || suffixAfter.hasPrefix("けど") || suffixAfter.hasPrefix("が")
                if !isNextPunctuation && !isContinuation {
                    result.insert("。", at: afterEnd)
                }
            }
            searchStart = result.index(after: range.lowerBound)
            if searchStart >= result.endIndex { break }
        }
    }

    let transitionWords = ["とりあえず", "ただ", "でも", "しかし", "ちなみに", "あと", "それから", "それで"]
    for word in transitionWords {
        var offset = 0
        while offset < result.count {
            guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                  let range = result.range(of: word, range: startIdx..<result.endIndex) else { break }
            if range.lowerBound > result.startIndex {
                let prevIndex = result.index(before: range.lowerBound)
                let prevChar = result[prevIndex]
                if word == "ただ" && (prevChar == "い" || prevChar == "わ" || prevChar == "ま") {
                    offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                    continue
                }
                if word == "でも" {
                    if prevChar == "な" || prevChar == "何" || prevChar == "誰" || prevChar == "ど" || prevChar == "い" {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                        continue
                    }
                    let sentenceEndPatterns = ["ました", "ません", "です", "ます", "だった", "でした", "ない"]
                    var hasSentenceEnd = false
                    for pattern in sentenceEndPatterns {
                        if result.distance(from: result.startIndex, to: range.lowerBound) >= pattern.count {
                            let patternStart = result.index(range.lowerBound, offsetBy: -pattern.count)
                            let preceding = String(result[patternStart..<range.lowerBound])
                            if preceding == pattern {
                                hasSentenceEnd = true
                                break
                            }
                        }
                    }
                    if !hasSentenceEnd {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                        continue
                    }
                }
                if word == "あと" && (prevChar >= "0" && prevChar <= "9" || prevChar == "分" || prevChar == "時" || prevChar == "日" || prevChar == "年") {
                    offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                    continue
                }
                if result.distance(from: result.startIndex, to: range.lowerBound) >= 2 {
                    let twoBack = result.index(range.lowerBound, offsetBy: -2)
                    let preceding = String(result[twoBack..<range.lowerBound])
                    if preceding == "では" {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                        continue
                    }
                }
                if prevChar != "。" && prevChar != "、" && prevChar != "？" && prevChar != "！" {
                    result.insert("。", at: range.lowerBound)
                    offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count + 1
                    continue
                }
            }
            offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
        }
    }
    for phrase in midSentenceBreakers.sorted(by: { $0.count > $1.count }) {
        var offset = 0
        while offset < result.count {
            guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                  let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }
            var insertedBefore = false
            if range.lowerBound > result.startIndex {
                let prevIndex = result.index(before: range.lowerBound)
                let prevChar = result[prevIndex]
                if prevChar != "。" && prevChar != "、" && prevChar != "？" && prevChar != "！" {
                    result.insert("。", at: range.lowerBound)
                    insertedBefore = true
                }
            }
            let newUpperBound = result.index(range.lowerBound, offsetBy: phrase.count + (insertedBefore ? 1 : 0))
            if newUpperBound < result.endIndex {
                let nextChar = result[newUpperBound]
                if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" {
                    result.insert("。", at: newUpperBound)
                }
            }
            offset = result.distance(from: result.startIndex, to: range.lowerBound) + phrase.count + (insertedBefore ? 2 : 1)
        }
    }

    let politeEndingsForMid = ["お願いいたします", "お願いします", "くださいませ", "ください", "でございます", "思います"]
    for phrase in politeEndingsForMid {
        var offset = 0
        while offset < result.count {
            guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                  let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }
            let afterEnd = range.upperBound
            if afterEnd < result.endIndex {
                let nextChar = result[afterEnd]
                if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" && nextChar != "よ" && nextChar != "ね" && nextChar != "か" && nextChar != "が" && nextChar != "け" {
                    result.insert("。", at: afterEnd)
                    offset = result.distance(from: result.startIndex, to: afterEnd) + 1
                    continue
                }
            }
            offset = result.distance(from: result.startIndex, to: range.lowerBound) + phrase.count
        }
    }

    let questionEndings = ["ですかね", "ますかね", "ですよね", "ますよね", "でしょうか", "ましょうか", "ですか", "ますか"]
    for ending in questionEndings {
        var offset = 0
        while offset < result.count {
            guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                  let range = result.range(of: ending, range: startIdx..<result.endIndex) else { break }
            let afterEnd = range.upperBound
            if afterEnd < result.endIndex {
                let nextChar = result[afterEnd]
                if (ending == "ですか" || ending == "ますか") && (nextChar == "ね" || nextChar == "よ") {
                    offset = result.distance(from: result.startIndex, to: range.lowerBound) + ending.count
                    continue
                }
                if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" {
                    result.insert("？", at: afterEnd)
                    offset = result.distance(from: result.startIndex, to: afterEnd) + 1
                    continue
                }
            } else if afterEnd == result.endIndex {
                result.append("？")
                break
            }
            offset = result.distance(from: result.startIndex, to: range.lowerBound) + ending.count
        }
    }

    let commaAfterConjunctions = ["けど", "けれど", "けれども", "だけど", "ですが", "ですけど"]
    for conj in commaAfterConjunctions.sorted(by: { $0.count > $1.count }) {
        var offset = 0
        while offset < result.count {
            guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                  let range = result.range(of: conj, range: startIdx..<result.endIndex) else { break }
            if range.upperBound < result.endIndex {
                let nextChar = result[range.upperBound]
                if nextChar != "。" && nextChar != "、" && nextChar != "？" && nextChar != "！" {
                    result.insert("、", at: range.upperBound)
                }
            }
            offset = result.distance(from: result.startIndex, to: range.lowerBound) + conj.count + 1
        }
    }

    let startersOnlyAtBeginning = ["はい", "いいえ", "うん", "ええ", "そうですね", "なるほど", "おはよう"]
    for starter in startersOnlyAtBeginning {
        if result.hasPrefix(starter) && result.count > starter.count {
            let afterStarter = result.dropFirst(starter.count)
            if let first = afterStarter.first, first != "。" && first != "、" {
                result = starter + "。" + String(afterStarter)
            }
        }
    }

    result = removePunctuationBeforeFinalParticles(result)
    result = removeLeadingFillers(result)

    return result
}

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let manifestPath = projectRoot.appendingPathComponent("benchmark-audio/punctuation-tests.json")

print("🔤 NiceVoice 後処理ベンチマーク")
print(String(repeating: "=", count: 60))

guard FileManager.default.fileExists(atPath: manifestPath.path) else {
    print("❌ punctuation-tests.json が見つかりません")
    exit(1)
}

guard let manifestData = try? Data(contentsOf: manifestPath),
      let testCases = try? JSONDecoder().decode([PunctuationTestCase].self, from: manifestData) else {
    print("❌ punctuation-tests.json の読み込みに失敗")
    exit(1)
}

var results: [TestResult] = []

for testCase in testCases {
    print("\n📝 テスト: \(testCase.id)")
    print("   説明: \(testCase.description)")
    print("   入力: \(testCase.input)")
    print("   期待: \(testCase.expected)")

    let actual = addLocalPunctuation(testCase.input)
    let passed = actual == testCase.expected

    results.append(TestResult(
        id: testCase.id,
        input: testCase.input,
        expected: testCase.expected,
        actual: actual,
        passed: passed
    ))

    let status = passed ? "✅" : "❌"
    print("   結果: \(actual)")
    print("   \(status) \(passed ? "合格" : "不合格")")
}

print("\n" + String(repeating: "=", count: 60))
print("📊 結果サマリー")
print(String(repeating: "=", count: 60))

let passedCount = results.filter { $0.passed }.count
let totalCount = results.count

print("合格: \(passedCount)/\(totalCount)")

if passedCount < totalCount {
    print("\n不合格のテスト:")
    for result in results where !result.passed {
        print("  ❌ \(result.id)")
        print("      入力: \(result.input)")
        print("      期待: \(result.expected)")
        print("      実際: \(result.actual)")
    }
}

exit(passedCount == totalCount ? 0 : 1)
