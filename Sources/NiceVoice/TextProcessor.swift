import Foundation

struct TextProcessor {
    let fillerSettings: FillerSettings
    let dictionaryEntries: [DictionaryEntry]

    private static let leadingFillers = ["あの", "えっと", "えーと"]
    private static let leadingFillerCleanupPrefixes = ["、", "。", "に", "もう", "ば"]
    private static let fillerPrefixes = ["あの", "その"]
    private static let fillerPronouns = ["私", "僕", "俺", "彼", "彼女", "あなた", "君"]

    private static let spaceVariants = [" ", "　"]
    private static let spacingPunctuations = ["。", "、", "？", "！", "?", "!", ".", ","]

    private static let builtInDictionary: [(String, String)] = [
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
        ("ディスコード", "Discord"),
        ("ワンパスワード", "1Password"),
        ("ジェミニ", "Gemini"),
        ("ナノバナナ", "Nano Banana"),
        ("API機", "APIキー"),
        ("クラウドフレア", "Cloudflare"),
        ("アンソロピック", "Anthropic"),
        ("反角", "半角"),
    ]

    private static let sentenceEndings = ["ました", "ません", "でした"]
    private static let transitionWords = ["とりあえず", "ただ", "でも", "しかし", "ちなみに", "あと", "それから", "それで"]
    private static let transitionSentenceEndPatterns = ["ました", "ません", "です", "ます", "だった", "でした", "ない"]
    private static let transitionTimeRelatedCharacters: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "分", "時", "日", "年"
    ]

    private static let greetingPhrases = [
        "ありがとうございます", "すみません",
        "こんにちは", "こんばんは", "おはようございます", "お疲れ様です", "お疲れさまです"
    ]
    private static let greetingPhrasesByLength: [String] = {
        Self.greetingPhrases.sorted { $0.count > $1.count }
    }()

    private static let politeEndings = ["お願いいたします", "お願いします", "くださいませ", "ください", "でございます", "思います"]
    private static let politeEndingSkipCharacters: Set<Character> = ["。", "、", "？", "！", "よ", "ね", "か", "が", "け"]

    private static let questionEndings = [
        "ですかね", "ますかね", "ですよね", "ますよね", "でしょうか", "ましょうか", "ですか", "ますか",
        "でしたっけ", "ましたっけ", "ですっけ", "ますっけ", "だっけ", "たっけ", "んだっけ"
    ]

    private static let conjunctions = ["けど", "けれど", "けれども", "だけど", "ですが", "ですけど"]
    private static let conjunctionsByLength: [String] = {
        Self.conjunctions.sorted { $0.count > $1.count }
    }()

    private static let starterPhrases = ["はい", "いいえ", "うん", "ええ", "そうですね", "なるほど", "おはよう"]

    private static let punctuationCharacters: Set<Character> = ["。", "、", "？", "！", "?", "!", ".", ","]
    private static let particleCharacters: Set<Character> = ["か", "が", "け", "ね", "よ"]

    func process(_ text: String, isFinal: Bool = true) -> String {
        let originalText = text
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        debugLog("🔤 [PUNCT] Input (\(isFinal ? "final" : "interim")): \(result)")

        result = removeFillers(from: result)
        guard !result.isEmpty else { return result }

        result = removeJapaneseWordSpaces(from: result)
        result = removeSpacesBeforePunctuation(from: result)
        result = applyDictionaryReplacements(to: result)
        result = normalizeJapanesePunctuation(in: result)
        result = removeTrailingRepetitions(from: result)
        if fillerSettings.addPunctuation {
            result = insertSentenceEndPunctuation(in: result)
            result = insertTransitionPunctuation(in: result)
            result = insertGreetingPunctuation(in: result)
            result = insertPoliteEndingPunctuation(in: result)
            result = insertQuestionMarks(in: result)
            result = insertConjunctionCommas(in: result)
            result = insertStarterPunctuation(in: result)
            result = removePunctuationBeforeFinalParticles(from: result)
        }
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

        for filler in Self.leadingFillers {
            if result.hasPrefix(filler) {
                result.removeFirst(filler.count)
            }
        }

        for filler in Self.leadingFillers {
            for prefix in Self.leadingFillerCleanupPrefixes {
                result = result.replacingOccurrences(of: "\(prefix)\(filler)", with: prefix)
            }
        }

        for prefix in Self.fillerPrefixes {
            for pronoun in Self.fillerPronouns {
                result = result.replacingOccurrences(of: prefix + pronoun, with: pronoun)
            }
        }

        return result
    }

    private func removeJapaneseWordSpaces(from text: String) -> String {
        var result = ""
        let chars = Array(text)
        for i in 0..<chars.count {
            if chars[i] == " " {
                let prevIsJapanese = i > 0 && isJapaneseCharacter(chars[i - 1])
                let nextIsJapanese = i + 1 < chars.count && isJapaneseCharacter(chars[i + 1])
                if prevIsJapanese || nextIsJapanese {
                    continue
                }
            }
            result.append(chars[i])
        }
        return result
    }

    private func isJapaneseCharacter(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v) ||
               (0x30A0...0x30FF).contains(v) ||
               (0x4E00...0x9FFF).contains(v) ||
               (0x3400...0x4DBF).contains(v) ||
               (0xFF00...0xFFEF).contains(v) {
                return true
            }
        }
        return false
    }

    private func removeSpacesBeforePunctuation(from text: String) -> String {
        var result = text
        for punct in Self.spacingPunctuations {
            for space in Self.spaceVariants {
                result = result.replacingOccurrences(of: "\(space)\(punct)", with: punct)
            }
        }
        return result
    }

    private func applyDictionaryReplacements(to text: String) -> String {
        var result = text

        for (reading, writing) in Self.builtInDictionary {
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
        guard !isExactRepeatedSequence(result) else { return result }

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

    private func isExactRepeatedSequence(_ text: String) -> Bool {
        guard text.count >= 2 else { return false }

        for unitLength in 1...(text.count / 2) {
            guard text.count.isMultiple(of: unitLength) else { continue }

            let unit = String(text.prefix(unitLength))
            let repeatCount = text.count / unitLength
            guard repeatCount >= 2 else { continue }

            if String(repeating: unit, count: repeatCount) == text {
                return true
            }
        }

        return false
    }

    private func insertSentenceEndPunctuation(in text: String) -> String {
        var result = text

        for ending in Self.sentenceEndings {
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

        for word in Self.transitionWords {
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
            var hasSentenceEnd = false
            for pattern in Self.transitionSentenceEndPatterns {
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
            if Self.transitionTimeRelatedCharacters.contains(prevChar) { return true }
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

        for phrase in Self.greetingPhrasesByLength {
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

        for phrase in Self.politeEndings {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: phrase, range: startIdx..<result.endIndex) else { break }

                let afterEnd = range.upperBound
                if afterEnd < result.endIndex {
                    let nextChar = result[afterEnd]
                    if !Self.politeEndingSkipCharacters.contains(nextChar) {
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

        for ending in Self.questionEndings {
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

        for conj in Self.conjunctionsByLength {
            var offset = 0
            while offset < result.count {
                guard let startIdx = result.index(result.startIndex, offsetBy: offset, limitedBy: result.endIndex),
                      let range = result.range(of: conj, range: startIdx..<result.endIndex) else { break }

                if range.upperBound < result.endIndex {
                    let nextChar = result[range.upperBound]
                    if !isPunctuation(nextChar) && !isSentenceFinalParticle(nextChar, in: result, at: range.upperBound) {
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

        for starter in Self.starterPhrases {
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

    private func removePunctuationBeforeFinalParticles(from text: String) -> String {
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

    private func isSentenceFinalParticle(_ char: Character, in text: String, at index: String.Index) -> Bool {
        guard char == "ね" || char == "よ" else { return false }
        let afterParticle = text.index(after: index)
        if afterParticle >= text.endIndex { return true }
        return isPunctuation(text[afterParticle])
    }

    private func normalizeJapanesePunctuation(in text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "?", with: "？")
        result = result.replacingOccurrences(of: "!", with: "！")
        return result
    }

    private func isPunctuation(_ char: Character) -> Bool {
        Self.punctuationCharacters.contains(char)
    }

    private func isParticle(_ char: Character) -> Bool {
        Self.particleCharacters.contains(char)
    }
}
