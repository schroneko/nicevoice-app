import Testing
import CoreGraphics
@testable import NiceVoice

struct FocusedElementInspectorTests {
    @Test
    func acceptsDirectTextInputs() {
        let snapshot = FocusedElementSnapshot(
            role: "AXTextField",
            editable: nil,
            enabled: true,
            hasSelectedTextRange: true,
            size: CGSize(width: 320, height: 24)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == true)
    }

    @Test
    func acceptsEditableWebAreas() {
        let snapshot = FocusedElementSnapshot(
            role: "AXWebArea",
            editable: true,
            enabled: true,
            hasSelectedTextRange: false,
            size: CGSize(width: 800, height: 600)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == true)
    }

    @Test
    func rejectsNonEditablePageElements() {
        let snapshot = FocusedElementSnapshot(
            role: "AXWebArea",
            editable: false,
            enabled: true,
            hasSelectedTextRange: false,
            size: CGSize(width: 800, height: 600)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == false)
    }

    @Test
    func rejectsDisabledElements() {
        let snapshot = FocusedElementSnapshot(
            role: "AXTextField",
            editable: true,
            enabled: false,
            hasSelectedTextRange: true,
            size: CGSize(width: 200, height: 24)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == false)
    }

    @Test
    func rejectsStaticHeadingsEvenWithSelectionRange() {
        let snapshot = FocusedElementSnapshot(
            role: "AXHeading",
            editable: nil,
            enabled: true,
            hasSelectedTextRange: true,
            size: CGSize(width: 640, height: 28)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == false)
    }

    @Test
    func rejectsNonEditableTextAreas() {
        let snapshot = FocusedElementSnapshot(
            role: "AXTextArea",
            editable: nil,
            enabled: true,
            hasSelectedTextRange: true,
            size: CGSize(width: 640, height: 400)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == false)
    }

    @Test
    func rejectsZeroSizedEditableElements() {
        let snapshot = FocusedElementSnapshot(
            role: "AXWebArea",
            editable: true,
            enabled: true,
            hasSelectedTextRange: true,
            size: CGSize(width: 0, height: 0)
        )

        #expect(FocusedElementInspector.acceptsTextInput(snapshot) == false)
    }
}
