import Testing
@testable import NiceVoice

struct ShortcutKeyTests {
    @Test
    func spaceShortcutUsesLongPressBehavior() {
        #expect(ShortcutKey.space.usesLongPressBehavior == true)
        #expect(ShortcutKey.fn.usesLongPressBehavior == false)
        #expect(ShortcutKey.custom.usesCustomKeyCombinationBehavior)
    }

    @Test
    func usageDescriptionReflectsLongPressBehavior() {
        let customShortcut = CustomShortcut(
            keyCode: 6,
            modifierFlags: [.command, .shift],
            keyDisplayName: "Z"
        )
        #expect(ShortcutKey.space.usageDescription(customShortcut: customShortcut) == "Space を長押しして録音")
        #expect(ShortcutKey.leftShift.usageDescription(customShortcut: customShortcut) == "左 Shift キーを押して録音")
        #expect(ShortcutKey.custom.usageDescription(customShortcut: customShortcut) == "Shift + Command + Z を押して録音")
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

    @Test
    func controlMShortcutRequiresControlWithoutOtherModifiers() {
        let customShortcut = CustomShortcut(
            keyCode: 46,
            modifierFlags: [.control],
            keyDisplayName: "M"
        )
        #expect(
            customShortcut.matches(
                keyCode: 46,
                modifierFlags: [.control]
            )
        )

        #expect(
            customShortcut.matches(
                keyCode: 46,
                modifierFlags: [.control, .shift]
            ) == false
        )

        #expect(
            customShortcut.matches(
                keyCode: 12,
                modifierFlags: [.control]
            ) == false
        )
    }

    @Test
    func controlMShortcutEndsWhenControlIsReleased() {
        let customShortcut = CustomShortcut(
            keyCode: 46,
            modifierFlags: [.control, .shift],
            keyDisplayName: "M"
        )
        #expect(customShortcut.hasRequiredModifiers([.control, .shift]))
        #expect(customShortcut.hasRequiredModifiers([.control]) == false)
        #expect(customShortcut.usesModifierKeyCode(59))
        #expect(customShortcut.usesModifierKeyCode(60))
        #expect(customShortcut.usesModifierKeyCode(46) == false)
    }

    @Test
    func customShortcutRoundTripsThroughStorage() {
        let shortcut = CustomShortcut(
            keyCode: 6,
            modifierFlags: [.command, .shift],
            keyDisplayName: "Z"
        )
        let restored = CustomShortcut(rawValue: shortcut.rawValue)
        #expect(restored == shortcut)
        #expect(restored?.displayName == "Shift + Command + Z")
    }
}
