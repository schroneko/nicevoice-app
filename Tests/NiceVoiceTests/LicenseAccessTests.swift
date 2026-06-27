import Foundation
import Testing
@testable import NiceVoice

struct LicenseAccessTests {
    @Test
    func licenseCodeNormalizesWhitespaceAndCase() {
        let code = LicenseCode(" nv-beta  abcd-1234 ")

        #expect(code?.value == "NV-BETAABCD-1234")
    }

    @Test
    func shortLicenseCodeIsRejected() {
        let code = LicenseCode("abc")

        #expect(code == nil)
    }

    @Test
    func entitlementWithoutExpiryIsActive() {
        let entitlement = BetaEntitlement(
            token: "token",
            activatedAt: Date(timeIntervalSince1970: 0),
            expiresAt: nil
        )

        #expect(entitlement.isActive(now: Date()) == true)
    }

    @Test
    func expiredEntitlementIsInactive() {
        let entitlement = BetaEntitlement(
            token: "token",
            activatedAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 10)
        )

        #expect(entitlement.isActive(now: Date(timeIntervalSince1970: 11)) == false)
    }

    @Test
    func missingEndpointIsNil() {
        let endpoint = LicenseConfiguration.endpointURL(
            environment: [:]
        )

        #expect(endpoint == nil)
    }

    @Test
    func endpointCanComeFromEnvironment() {
        let endpoint = LicenseConfiguration.endpointURL(
            environment: ["NICEVOICE_LICENSE_API_URL": "https://example.com/license"]
        )

        #expect(endpoint?.absoluteString == "https://example.com/license")
    }
}
