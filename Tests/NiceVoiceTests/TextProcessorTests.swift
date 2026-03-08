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
}
