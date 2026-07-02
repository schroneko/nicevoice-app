import Testing
@testable import NiceVoice

struct AppFeatureFlagsTests {
    @Test
    func developerToolsAreDisabledInReleaseByDefault() {
        let isEnabled = AppFeatureFlags.isDeveloperToolsEnabled(
            build: .release,
            environment: [:]
        )

        #expect(isEnabled == false)
    }

    @Test
    func developerToolsCanBeEnabledExplicitlyInRelease() {
        let isEnabled = AppFeatureFlags.isDeveloperToolsEnabled(
            build: .release,
            environment: ["NICEVOICE_ENABLE_DEVELOPER_UI": "1"]
        )

        #expect(isEnabled == true)
    }

    @Test
    func developerToolsCanBeDisabledExplicitlyInDebug() {
        let isEnabled = AppFeatureFlags.isDeveloperToolsEnabled(
            build: .debug,
            environment: ["NICEVOICE_DISABLE_DEVELOPER_UI": "1"]
        )

        #expect(isEnabled == false)
    }

    @Test
    func regularUsersDoNotSeeDeveloperOnlyEngines() {
        let engines = TranscriptionEngine.availableEngines(developerToolsEnabled: false)

        #expect(engines == [.speechAnalyzer, .voxtralLocal])
    }

    @Test
    func storedDeveloperEngineFallsBackToVoxtralForRegularUsers() {
        let engine = TranscriptionEngine.normalized(
            rawValue: TranscriptionEngine.qwen3ASR.rawValue,
            developerToolsEnabled: false
        )

        #expect(engine == .voxtralLocal)
    }

    @Test
    func localEnginesWaitLongerForFinalResults() {
        #expect(TranscriptionEngine.voxtralLocal.finalResultTimeoutSeconds == Constants.Timing.localASRFinalResultTimeoutSeconds)
        #expect(TranscriptionEngine.qwen3ASR.finalResultTimeoutSeconds == Constants.Timing.localASRFinalResultTimeoutSeconds)
        #expect(TranscriptionEngine.speechAnalyzer.finalResultTimeoutSeconds == Constants.Timing.speechAnalyzerFinalResultTimeoutSeconds)
    }

    @Test
    func developerDiagnosticsAreHiddenForRegularUsers() {
        let diagnostics = DependencyDiagnostics.snapshot(
            build: .release,
            developerToolsEnabled: false,
            environment: [:]
        )

        #expect(diagnostics.contains(where: { $0.id == CommandLineTool.uvx.rawValue }) == false)
        #expect(diagnostics.contains(where: { $0.id == CommandLineTool.hf.rawValue }) == false)
        #expect(diagnostics.contains(where: { $0.id == "server-resources" }) == false)
    }
}
