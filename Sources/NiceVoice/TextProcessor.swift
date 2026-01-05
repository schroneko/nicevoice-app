import Foundation

struct TextProcessor {
    let fillerSettings: FillerSettings
    let dictionaryEntries: [DictionaryEntry]

    func process(_ text: String, isFinal: Bool = true) -> String {
        let originalText = text
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        debugLog("🔤 [PUNCT] Input (\(isFinal ? "final" : "interim")): \(result)")

        result = removeFillers(from: result)
        guard !result.isEmpty else { return result }

        result = removeSpacesBeforePunctuation(from: result)
        result = applyDictionaryReplacements(to: result)
        result = removeTrailingRepetitions(from: result)
        result = insertSentenceEndPunctuation(in: result)
        result = insertTransitionPunctuation(in: result)
        result = insertGreetingPunctuation(in: result)
        result = insertPoliteEndingPunctuation(in: result)
        result = insertQuestionMarks(in: result)
        result = insertConjunctionCommas(in: result)
        result = insertStarterPunctuation(in: result)
        result = removeLeadingFillers(from: result)

        if !isFinal {
            result = removeTrailingSentenceEnd(from: result)
        }

        if result != originalText.trimmingCharacters(in: .whitespacesAndNewlines) {
            debugLog("🔤 [PUNCT] Output (\(isFinal ? "final" : "interim")): \(result)")
        }
        return result
    }

    private func removeFillers(from text: String) -> String {
        guard fillerSettings.removeFillers else { return text }
        var result = text

        for filler in fillerSettings.allEnabledFillers {
            result = result.replacingOccurrences(of: filler, with: "")
        }

        result = removeLeadingFillers(from: result)

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "  ", with: " ")
        return result
    }

    private func removeLeadingFillers(from text: String) -> String {
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

    private func removeSpacesBeforePunctuation(from text: String) -> String {
        var result = text
        let punctuations = ["。", "、", "？", "！", "?", "!", ".", ","]
        for punct in punctuations {
            result = result.replacingOccurrences(of: " \(punct)", with: punct)
            result = result.replacingOccurrences(of: "　\(punct)", with: punct)
        }
        return result
    }

    private func applyDictionaryReplacements(to text: String) -> String {
        var result = text

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
            ("ジェミニ", "Gemini"),
            ("ナノバナナ", "Nano Banana"),
        ]
        for (reading, writing) in builtInDictionary {
            result = result.replacingOccurrences(of: reading, with: writing)
        }

        for entry in dictionaryEntries where entry.isEnabled {
            result = result.replacingOccurrences(of: entry.reading, with: entry.writing)
        }
        return result
    }

    private func removeTrailingRepetitions(from text: String) -> String {
        var result = text
        let lastChars = String(result.suffix(min(10, result.count)))
        let containsLatin = lastChars.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic }

        guard !containsLatin else { return result }

        for suffixLen in (2...4).reversed() {
            guard result.count > suffixLen * 2 else { continue }
            let suffix = String(result.suffix(suffixLen))
            let beforeSuffix = String(result.dropLast(suffixLen))
            if beforeSuffix.hasSuffix(suffix) { continue }

            for checkLen in (suffixLen + 1)...(suffixLen + 3) {
                guard beforeSuffix.count >= checkLen else { continue }
                let candidate = String(beforeSuffix.suffix(checkLen))
                if candidate.hasPrefix(suffix) {
                    result = beforeSuffix
                    break
                }
            }
        }
        return result
    }

    private func insertSentenceEndPunctuation(in text: String) -> String {
        var result = text
        let sentenceEndings = ["ました", "ません", "でした"]

        for ending in sentenceEndings {
            var searchStart = result.startIndex
            while let range = result.range(of: ending, range: searchStart..<result.endIndex) {
                let afterEnd = range.upperBound
                if afterEnd < result.endIndex {
                    let nextChar = result[afterEnd]
                    let isNextPunctuation = isPunctuation(nextChar) || isParticle(nextChar)
                    let suffixAfter = String(result[afterEnd...])
                    let isContinuation = ["でした", "っけ", "よね", "けど", "が"].contains { suffixAfter.hasPrefix($0) }

                    if !isNextPunctuation && !isContinuation {
                        result.insert("。", at: afterEnd)
                    }
                }
                searchStart = result.index(after: range.lowerBound)
                if searchStart >= result.endIndex { break }
            }
        }
        return result
    }

    private func insertTransitionPunctuation(in text: String) -> String {
        var result = text
        let transitionWords = ["とりあえず", "ただ", "でも", "しかし", "ちなみに", "あと", "それから", "それで"]

        for word in transitionWords {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: word, range: startIdx..<result.endIndex) else { break }

                if range.lowerBound > result.startIndex {
                    let prevIndex = result.index(before: range.lowerBound)
                    let prevChar = result[prevIndex]

                    if shouldSkipTransitionWord(word, prevChar: prevChar, in: result, at: range) {
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
                        continue
                    }

                    if !isPunctuation(prevChar) {
                        result.insert("。", at: range.lowerBound)
                        offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count + 1
                        continue
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + word.count
            }
        }
        return result
    }

    private func shouldSkipTransitionWord(_ word: String, prevChar: Character, in text: String, at range: Range<String.Index>) -> Bool {
        if word == "ただ" && ["い", "わ", "ま"].contains(String(prevChar)) {
            return true
        }

        if word == "でも" {
            if ["な", "何", "誰", "ど", "い"].contains(String(prevChar)) {
                return true
            }
            let sentenceEndPatterns = ["ました", "ません", "です", "ます", "だった", "でした", "ない"]
            var hasSentenceEnd = false
            for pattern in sentenceEndPatterns {
                if text.distance(from: text.startIndex, to: range.lowerBound) >= pattern.count {
                    let patternStart = text.index(range.lowerBound, offsetBy: -pattern.count)
                    let preceding = String(text[patternStart..<range.lowerBound])
                    if preceding == pattern {
                        hasSentenceEnd = true
                        break
                    }
                }
            }
            if !hasSentenceEnd { return true }
        }

        if word == "あと" {
            let timeRelatedChars: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "分", "時", "日", "年"]
            if timeRelatedChars.contains(prevChar) { return true }
        }

        if text.distance(from: text.startIndex, to: range.lowerBound) >= 2 {
            let twoBack = text.index(range.lowerBound, offsetBy: -2)
            let preceding = String(text[twoBack..<range.lowerBound])
            if preceding == "では" { return true }
        }

        return false
    }

    private func insertGreetingPunctuation(in text: String) -> String {
        var result = text
        let greetings = [
            "ありがとうございます", "すみません",
            "こんにちは", "こんばんは", "おはようございます", "お疲れ様です", "お疲れさまです"
        ]

        for phrase in greetings.sorted(by: { $0.count > $1.count }) {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }

                var insertedBefore = false
                if range.lowerBound > result.startIndex {
                    let prevIndex = result.index(before: range.lowerBound)
                    let prevChar = result[prevIndex]
                    if !isPunctuation(prevChar) {
                        result.insert("。", at: range.lowerBound)
                        insertedBefore = true
                    }
                }

                let newUpperBound = result.index(range.lowerBound, offsetBy: phrase.count + (insertedBefore ? 1 : 0))
                if newUpperBound < result.endIndex {
                    let nextChar = result[newUpperBound]
                    if !isPunctuation(nextChar) {
                        result.insert("。", at: newUpperBound)
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + phrase.count + (insertedBefore ? 2 : 1)
            }
        }
        return result
    }

    private func insertPoliteEndingPunctuation(in text: String) -> String {
        var result = text
        let politeEndings = ["お願いいたします", "お願いします", "くださいませ", "ください", "でございます", "思います"]

        for phrase in politeEndings {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }

                let afterEnd = range.upperBound
                if afterEnd < result.endIndex {
                    let nextChar = result[afterEnd]
                    let skipChars: [Character] = ["。", "、", "？", "！", "よ", "ね", "か", "が", "け"]
                    if !skipChars.contains(nextChar) {
                        result.insert("。", at: afterEnd)
                        offset = result.distance(from: result.startIndex, to: afterEnd) + 1
                        continue
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + phrase.count
            }
        }
        return result
    }

    private func insertQuestionMarks(in text: String) -> String {
        var result = text
        let questionEndings = [
            "ですかね", "ますかね", "ですよね", "ますよね", "でしょうか", "ましょうか", "ですか", "ますか",
            "でしたっけ", "ましたっけ", "ですっけ", "ますっけ", "だっけ", "たっけ", "んだっけ"
        ]

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
                    if !isPunctuation(nextChar) {
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
        return result
    }

    private func insertConjunctionCommas(in text: String) -> String {
        var result = text
        let conjunctions = ["けど", "けれど", "けれども", "だけど", "ですが", "ですけど"]

        for conj in conjunctions.sorted(by: { $0.count > $1.count }) {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: conj, range: startIdx..<result.endIndex) else { break }

                if range.upperBound < result.endIndex {
                    let nextChar = result[range.upperBound]
                    if !isPunctuation(nextChar) {
                        result.insert("、", at: range.upperBound)
                    }
                }
                offset = result.distance(from: result.startIndex, to: range.lowerBound) + conj.count + 1
            }
        }
        return result
    }

    private func insertStarterPunctuation(in text: String) -> String {
        var result = text
        let starters = ["はい", "いいえ", "うん", "ええ", "そうですね", "なるほど", "おはよう"]

        for starter in starters {
            if result.hasPrefix(starter) && result.count > starter.count {
                let afterStarter = result.dropFirst(starter.count)
                if let first = afterStarter.first, first != "。" && first != "、" {
                    result = starter + "。" + String(afterStarter)
                }
            }
        }
        return result
    }

    private func removeTrailingSentenceEnd(from text: String) -> String {
        var result = text
        while result.hasSuffix("。") {
            result = String(result.dropLast())
        }
        return result
    }

    private func isPunctuation(_ char: Character) -> Bool {
        ["。", "、", "？", "！"].contains(char)
    }

    private func isParticle(_ char: Character) -> Bool {
        ["か", "が", "け", "ね", "よ"].contains(char)
    }
}
