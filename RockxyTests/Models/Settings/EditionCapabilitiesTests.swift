@testable import Rockxy
import Testing

struct EditionCapabilitiesTests {
    // MARK: - ProductEdition Resolution

    @Test("resolves to community when info dictionary is nil")
    func resolveNilDictionary() {
        #expect(ProductEdition.resolve(from: nil) == .community)
    }

    @Test("resolves to community when info dictionary is empty")
    func resolveEmptyDictionary() {
        #expect(ProductEdition.resolve(from: [:]) == .community)
    }

    @Test("resolves to community when key is missing")
    func resolveMissingKey() {
        #expect(ProductEdition.resolve(from: ["other": "value"]) == .community)
    }

    @Test("resolves to pro")
    func resolvePro() {
        #expect(ProductEdition.resolve(from: ["RockxyProductEdition": "pro"]) == .pro)
    }

    @Test("resolves to enterprise")
    func resolveEnterprise() {
        #expect(ProductEdition.resolve(from: ["RockxyProductEdition": "enterprise"]) == .enterprise)
    }

    @Test("resolves to community for unrecognized value")
    func resolveUnknown() {
        #expect(ProductEdition.resolve(from: ["RockxyProductEdition": "unknown"]) == .community)
    }

    @Test("resolves case-insensitively")
    func resolveCaseInsensitive() {
        #expect(ProductEdition.resolve(from: ["RockxyProductEdition": "PRO"]) == .pro)
        #expect(ProductEdition.resolve(from: ["RockxyProductEdition": "Community"]) == .community)
    }

    // MARK: - EditionCapabilities

    @Test("community has 8 workspace tabs")
    func communityWorkspaceTabs() {
        let caps = EditionCapabilities.capabilities(for: .community)
        #expect(caps.maxWorkspaceTabs == 8)
    }

    @Test("pro has 20 workspace tabs")
    func proWorkspaceTabs() {
        let caps = EditionCapabilities.capabilities(for: .pro)
        #expect(caps.maxWorkspaceTabs == 20)
    }

    @Test("enterprise has 20 workspace tabs")
    func enterpriseWorkspaceTabs() {
        let caps = EditionCapabilities.capabilities(for: .enterprise)
        #expect(caps.maxWorkspaceTabs == 20)
    }
}
