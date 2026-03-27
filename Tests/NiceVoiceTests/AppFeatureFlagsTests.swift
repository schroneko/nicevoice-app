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

        #expect(engines == [.speechAnalyzer, .deepgram])
    }

    @Test
    func storedDeveloperEngineFallsBackToSpeechAnalyzerForRegularUsers() {
        let engine = TranscriptionEngine.normalized(
            rawValue: TranscriptionEngine.voxtralLocal.rawValue,
            developerToolsEnabled: false
        )

        #expect(engine == .speechAnalyzer)
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
