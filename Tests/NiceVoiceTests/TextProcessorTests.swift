import Testing
@testable import NiceVoice

struct TextProcessorTests {
    @Test
    func builtInDictionaryAndQuestionNormalizationAreApplied() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("クラウドフレア?")

        #expect(result == "Cloudflare？")
    }

    @Test
    func builtInDeveloperDictionaryTermsAreApplied() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("エルメスエージェントとコーデックスCLIとコーデックスとCloudflareワーカーズ")

        #expect(result == "Hermes AgentとCodex CLIとCodexとCloudflare Workers")
    }

    @Test
    func interimProcessingDoesNotLeaveTrailingSentenceEnd() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("今日はありがとうございました", isFinal: false)

        #expect(result == "今日はありがとうございました")
    }

    @Test
    func userDictionaryEntriesOverrideRecognizedTerms() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: [
                DictionaryEntry(reading: "ないすぼいす", writing: "NiceVoice")
            ]
        )

        let result = processor.process("ないすぼいすを起動します")

        #expect(result == "NiceVoiceを起動します")
    }

    @Test
    func repeatedGreetingPhrasesRemainIntact() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("こんにちはこんにちはこんにちはこんにちは")

        #expect(result == "こんにちは。こんにちは。こんにちは。こんにちは")
    }

    @Test
    func politeMorningGreetingRemainsIntact() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("おはようございます")

        #expect(result == "おはようございます")
    }

    @Test
    func trailingPartialRepeatIsStillTrimmed() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("こんにちはこんに")

        #expect(result == "こんにちは")
    }

    @Test
    func spokenFollowupClausesAreSplitMoreNaturally() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("ありがとうございますめちゃくちゃいい感じです今動いていますであの変換した時に切り替えた時になんかいい感じのUIをつけたいんですけれどお願いしてもいいですか")

        #expect(result == "ありがとうございます。めちゃくちゃいい感じです。今動いています。で、あの変換した時に切り替えた時になんかいい感じのUIをつけたいんですけれど、お願いしてもいいですか？")
    }

    @Test
    func plainSentenceEndingDoesNotBreakReasonClauses() {
        let processor = TextProcessor(
            fillerSettings: FillerSettings(),
            dictionaryEntries: []
        )

        let result = processor.process("この形で大丈夫ですからそのまま進めてください")

        #expect(result == "この形で大丈夫ですからそのまま進めてください")
    }
}
