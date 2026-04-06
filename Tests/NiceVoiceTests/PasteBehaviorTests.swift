import Testing
@testable import NiceVoice

struct PasteBehaviorTests {
    @Test
    func codexClipboardRestoreUsesLongerDelay() {
        let codexDelay = AppState.clipboardRestoreDelay(for: "com.openai.codex")
        let defaultDelay = AppState.clipboardRestoreDelay(for: "com.apple.TextEdit")

        #expect(codexDelay == Constants.Timing.pastePostDelaySecondsForCodex)
        #expect(codexDelay > defaultDelay)
    }

    @Test
    func clipboardRestoreOnlyRunsWhileInjectedTextIsStillPresent() {
        #expect(
            AppState.shouldRestoreClipboard(
                previousContents: "S_1_1",
                currentContents: "文字起こし結果",
                pastedText: "文字起こし結果"
            )
        )

        #expect(
            AppState.shouldRestoreClipboard(
                previousContents: "S_1_1",
                currentContents: "ユーザーが別でコピーした内容",
                pastedText: "文字起こし結果"
            ) == false
        )

        #expect(
            AppState.shouldRestoreClipboard(
                previousContents: nil,
                currentContents: "文字起こし結果",
                pastedText: "文字起こし結果"
            ) == false
        )
    }

    @Test
    func floatingPanelShowsOnlyWhenInputTargetExists() {
        #expect(
            AppState.shouldShowFloatingPanelForRecording(
                hasTextInputTarget: true,
                spotlightOpen: false
            )
        )

        #expect(
            AppState.shouldShowFloatingPanelForRecording(
                hasTextInputTarget: false,
                spotlightOpen: true
            )
        )

        #expect(
            AppState.shouldShowFloatingPanelForRecording(
                hasTextInputTarget: false,
                spotlightOpen: false
            ) == false
        )
    }

    @Test
    func recordingErrorsStaySilentWithoutVisibleInputTarget() {
        #expect(
            AppState.shouldPresentErrorPanelForRecordingContext(
                isActiveRecordingContext: true,
                hasVisibleInputTarget: true
            )
        )

        #expect(
            AppState.shouldPresentErrorPanelForRecordingContext(
                isActiveRecordingContext: true,
                hasVisibleInputTarget: false
            ) == false
        )

        #expect(
            AppState.shouldPresentErrorPanelForRecordingContext(
                isActiveRecordingContext: false,
                hasVisibleInputTarget: false
            )
        )
    }
}
