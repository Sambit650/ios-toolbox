//
//  RemoteFlagProviderTests.swift
//  ToolboxFeatureFlags
//

import Foundation
import Testing
import ToolboxNetworking

@testable import ToolboxFeatureFlags

extension FlagKey where Value == Bool {
  fileprivate static let remoteOn = FlagKey("remote_on", default: false)
}

/// Thread-safe mutable box for `@Sendable` closures.
private final class Box<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: T
  init(_ value: T) { _value = value }
  var value: T {
    get { lock.lock(); defer { lock.unlock() }; return _value }
    set { lock.lock(); _value = newValue; lock.unlock() }
  }
}

private struct Offline: Error {}

private func json(_ on: Bool) -> Data { Data(#"{"default":{"remote_on":\#(on)}}"#.utf8) }

private func tempCache() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("ff-\(UUID().uuidString)/flags.json")
}

@MainActor
struct RemoteFlagProviderTests {

  @Test func appliesFetchedValuesAndReportsChange() async {
    let provider = RemoteFlagProvider(fetch: { json(true) }, cacheURL: nil)
    let flags = FeatureFlags(providers: [provider])
    #expect(flags[.remoteOn] == false)
    #expect(await provider.refresh() == true)
    #expect(flags[.remoteOn] == true)
    #expect(await provider.refresh(force: true) == false)  // same payload
  }

  @Test func failureAndInvalidJSONKeepExistingValues() async {
    let payload = Box<Result<Data, Offline>>(.success(json(true)))
    let provider = RemoteFlagProvider(fetch: { try payload.value.get() }, cacheURL: nil)
    await provider.refresh()

    payload.value = .failure(Offline())
    #expect(await provider.refresh(force: true) == false)
    payload.value = .success(Data("not json".utf8))
    #expect(await provider.refresh(force: true) == false)

    #expect(provider.value(for: "remote_on", context: FlagContext()) == .bool(true))
  }

  @Test func throttlesUntilIntervalElapsesUnlessForced() async {
    let calls = Box(0)
    let clock = Box(Date(timeIntervalSince1970: 1_000))
    let provider = RemoteFlagProvider(
      fetch: { calls.value += 1; return json(true) },
      cacheURL: nil, refreshInterval: 60, now: { clock.value })

    await provider.refresh()
    await provider.refresh()
    #expect(calls.value == 1)
    clock.value = clock.value.addingTimeInterval(61)
    await provider.refresh()
    #expect(calls.value == 2)
    await provider.refresh(force: true)
    #expect(calls.value == 3)
  }

  @Test func failedFetchDoesNotStartThrottleWindow() async {
    let ok = Box(false)
    let provider = RemoteFlagProvider(
      fetch: { if ok.value { return json(true) } else { throw Offline() } },
      cacheURL: nil, refreshInterval: 3600)
    await provider.refresh()
    ok.value = true
    #expect(await provider.refresh() == true)
  }

  @Test func cachedValuesLoadAtInitForOfflineLaunch() async {
    let cache = tempCache()
    defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }

    await RemoteFlagProvider(fetch: { json(true) }, cacheURL: cache).refresh()

    let offline = RemoteFlagProvider(fetch: { throw Offline() }, cacheURL: cache)
    #expect(offline.value(for: "remote_on", context: FlagContext()) == .bool(true))
  }

  @Test func invalidResponseDoesNotOverwriteCache() async {
    let cache = tempCache()
    defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }

    await RemoteFlagProvider(fetch: { json(true) }, cacheURL: cache).refresh()
    await RemoteFlagProvider(fetch: { Data("oops".utf8) }, cacheURL: cache).refresh(force: true)

    let reloaded = RemoteFlagProvider(fetch: { throw Offline() }, cacheURL: cache)
    #expect(reloaded.value(for: "remote_on", context: FlagContext()) == .bool(true))
  }

  @Test func fetchesThroughAPIClient() async {
    let transport = MockTransport { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json(true), response)
    }
    let client = APIClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)
    let provider = RemoteFlagProvider(
      client: client, endpoint: Endpoint(path: "flags"), cacheURL: tempCache())
    #expect(await provider.refresh() == true)
    #expect(provider.value(for: "remote_on", context: FlagContext()) == .bool(true))
  }

  @Test func featureFlagsRefreshNotifiesObservers() async {
    let provider = RemoteFlagProvider(fetch: { json(true) }, cacheURL: nil)
    let flags = FeatureFlags(providers: [provider])
    var seen: [Bool] = []
    let cancellable = flags.publisher(for: .remoteOn).sink { seen.append($0) }
    await flags.refresh(provider)
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(seen == [false, true])
    cancellable.cancel()
  }
}
