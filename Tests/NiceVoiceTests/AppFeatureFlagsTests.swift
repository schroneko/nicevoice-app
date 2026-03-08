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
}
