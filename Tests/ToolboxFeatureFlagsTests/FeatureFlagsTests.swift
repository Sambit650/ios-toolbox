//
//  FeatureFlagsTests.swift
//  ToolboxFeatureFlags
//

import Combine
import Foundation
import Testing

@testable import ToolboxFeatureFlags

extension FlagKey where Value == Bool {
  fileprivate static let checkout = FlagKey("checkout", default: false)
  fileprivate static let banner = FlagKey("banner", default: false)
}
extension FlagKey where Value == Int {
  fileprivate static let maxItems = FlagKey("max_items", default: 5)
}
extension FlagKey where Value == String {
  fileprivate static let theme = FlagKey("theme", default: "light")
}

@MainActor
struct FeatureFlagsTests {

  @Test func fallsBackToDefault() {
    let flags = FeatureFlags(providers: [])
    #expect(flags[.checkout] == false)
    #expect(flags[.maxItems] == 5)
    #expect(flags[.theme] == "light")
  }

  @Test func earlierProviderWins() {
    let remote = MemoryFlagProvider(values: ["checkout": .bool(true)])
    let bundled = MemoryFlagProvider(values: ["checkout": .bool(false), "max_items": .int(9)])
    let flags = FeatureFlags(providers: [remote, bundled])
    #expect(flags[.checkout] == true)
    #expect(flags[.maxItems] == 9)
  }

  @Test func typeMismatchFallsThrough() {
    let bad = MemoryFlagProvider(values: ["max_items": .string("many")])
    let good = MemoryFlagProvider(values: ["max_items": .int(3)])
    #expect(FeatureFlags(providers: [bad, good])[.maxItems] == 3)
    #expect(FeatureFlags(providers: [bad])[.maxItems] == 5)
  }

  @Test func overridesBeatProviders() {
    let flags = FeatureFlags(providers: [MemoryFlagProvider(values: ["checkout": .bool(false)])])
    flags.setOverride(true, for: .checkout)
    #expect(flags[.checkout] == true)
    flags.removeOverride(for: .checkout)
    #expect(flags[.checkout] == false)
  }

  @Test func rulesTargetUsers() throws {
    let json = """
      {"default": {"banner": {"value": false,
        "rules": [{"attribute": "isPremium", "equals": true, "value": true}]}}}
      """
    let flags = FeatureFlags(providers: [try JSONFlagProvider(data: Data(json.utf8))])
    #expect(flags[.banner] == false)
    flags.context = FlagContext(attributes: ["isPremium": .bool(true)])
    #expect(flags[.banner] == true)
  }

  @Test func jsonEnvironmentOverridesDefault() throws {
    let json = """
      {"default": {"checkout": false, "theme": "light"}, "staging": {"checkout": true}}
      """
    let data = Data(json.utf8)
    let staging = FeatureFlags(providers: [try JSONFlagProvider(data: data, environment: .staging)])
    let prod = FeatureFlags(providers: [try JSONFlagProvider(data: data, environment: .production)])
    #expect(staging[.checkout] == true)
    #expect(prod[.checkout] == false)
    #expect(staging[.theme] == "light")
  }

  @Test func userDefaultsProviderRoundTripsTypes() throws {
    let suite = "ff-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let provider = UserDefaultsFlagProvider(defaults: defaults)
    provider.set(.bool(true), for: "checkout")
    provider.set(.int(1), for: "max_items")
    provider.set(.string("dark"), for: "theme")
    let flags = FeatureFlags(providers: [provider])
    #expect(flags[.checkout] == true)
    #expect(flags[.maxItems] == 1)
    #expect(flags[.theme] == "dark")
    provider.remove("theme")
    #expect(flags[.theme] == "light")
  }

  @Test func publisherEmitsOnChangeOnly() {
    let flags = FeatureFlags(providers: [])
    var seen: [Bool] = []
    let cancellable = flags.publisher(for: .checkout).sink { seen.append($0) }
    flags.setOverride(true, for: .checkout)
    flags.reload()  // no change, no emission
    flags.removeOverride(for: .checkout)
    #expect(seen == [false, true, false])
    cancellable.cancel()
  }
}
