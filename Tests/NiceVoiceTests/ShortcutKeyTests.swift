import Testing
@testable import NiceVoice

struct ShortcutKeyTests {
    @Test
    func spaceShortcutUsesLongPressBehavior() {
        #expect(ShortcutKey.space.usesLongPressBehavior == true)
        #expect(ShortcutKey.fn.usesLongPressBehavior == false)
    }

    @Test
    func usageDescriptionReflectsLongPressBehavior() {
        #expect(ShortcutKey.space.usageDescription == "Space を長押しして録音")
        #expect(ShortcutKey.leftShift.usageDescription == "左 Shift キーを押して録音")
    }

    @Test
    func spaceShortcutNeedsLongerHoldThanATap() {
        #expect(ShortcutKey.space.longPressDelay == 0.45)
        #expect(ShortcutKey.fn.longPressDelay == nil)
    }

    @Test
    func japaneseLanguageCodesAreTreatedAsImeInput() {
        #expect(KeyMonitor.inputSourceLanguagesUseJapanese(["ja"]) == true)
        #expect(KeyMonitor.inputSourceLanguagesUseJapanese(["ja-JP"]) == true)
        #expect(KeyMonitor.inputSourceLanguagesUseJapanese(["en"]) == false)
    }
}
