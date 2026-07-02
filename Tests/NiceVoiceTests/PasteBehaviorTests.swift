import Testing
@testable import NiceVoice

struct PasteBehaviorTests {
    @Test
    func clipboardRestoreUsesConfiguredDelay() {
        #expect(TextInsertionController.clipboardRestoreDelay() == Constants.Timing.pastePostDelaySeconds)
    }

    @Test
    func clipboardRestoreOnlyRunsWhileInjectedTextIsStillPresent() {
        #expect(
            TextInsertionController.shouldRestoreClipboard(
                previousContents: "S_1_1",
                currentContents: "文字起こし結果",
                pastedText: "文字起こし結果"
            )
        )

        #expect(
            TextInsertionController.shouldRestoreClipboard(
                previousContents: "S_1_1",
                currentContents: "ユーザーが別でコピーした内容",
                pastedText: "文字起こし結果"
            ) == false
        )

        #expect(
            TextInsertionController.shouldRestoreClipboard(
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
