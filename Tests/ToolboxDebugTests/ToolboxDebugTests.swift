import Foundation
import Testing
import ToolboxNetworking

@testable import ToolboxDebug

private func makeEntries() async throws -> [NetworkLogEntry] {
  let store = await NetworkLogStore.sample()
  return await store.entries
}

struct SampleTrafficTests {
  @Test func sampleStoreHasMixedTraffic() async throws {
    let entries = try await makeEntries()
    #expect(entries.contains { $0.fromCache })
    #expect(entries.contains { $0.isSuccess })
    #expect(entries.contains { $0.statusCode == 404 })
    #expect(entries.contains { $0.statusCode == nil && $0.errorDescription != nil })
    #expect(entries.contains { $0.attempt > 1 })
  }
}

struct FilterTests {
  @Test func statusFilters() async throws {
    let entries = try await makeEntries()
    #expect(NetworkLogFilter(status: .cached).apply(to: entries).allSatisfy { $0.fromCache })
    #expect(NetworkLogFilter(status: .success).apply(to: entries).allSatisfy { $0.isSuccess })
    #expect(NetworkLogFilter(status: .failed).apply(to: entries).allSatisfy { !$0.isSuccess })
    let all = NetworkLogFilter().apply(to: entries)
    #expect(all.count == entries.count)
  }

  @Test func queryMatchesURLStatusAndBodies() async throws {
    let entries = try await makeEntries()
    #expect(!NetworkLogFilter(query: "v1/login").apply(to: entries).isEmpty)
    #expect(NetworkLogFilter(query: "404").apply(to: entries).allSatisfy { $0.statusCode == 404 })
    #expect(!NetworkLogFilter(query: "linus").apply(to: entries).isEmpty)  // response body, case-insensitive
    #expect(!NetworkLogFilter(query: "hunter2").apply(to: entries).isEmpty)  // request body
    #expect(NetworkLogFilter(query: "definitely-not-present").apply(to: entries).isEmpty)
  }

  @Test func whitespaceOnlyQueryIsInactive() {
    #expect(!NetworkLogFilter(query: "   ").isActive)
    #expect(NetworkLogFilter(query: "x").isActive)
  }
}

struct FormattingTests {
  @Test func prettyPrintsJSONWithSortedKeys() {
    let text = BodyFormatter.format(Data(#"{"b":1,"a":"x/y"}"#.utf8))
    #expect(text == "{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}")
  }

  @Test func fallsBackToPlainTextAndBinary() {
    #expect(BodyFormatter.format(Data("hello".utf8)) == "hello")
    #expect(BodyFormatter.format(Data([0xFF, 0xFE, 0xFD])) == "<3 bytes of binary data>")
  }

  @Test func emptyBodiesAreNil() {
    #expect(BodyFormatter.format(nil) == nil)
    #expect(BodyFormatter.format(Data()) == nil)
  }

  @Test func statusCategories() {
    #expect(StatusCategory(statusCode: 204) == .success)
    #expect(StatusCategory(statusCode: 301) == .redirect)
    #expect(StatusCategory(statusCode: 404) == .clientError)
    #expect(StatusCategory(statusCode: 503) == .serverError)
    #expect(StatusCategory(statusCode: nil) == .failure)
  }

  @Test func displayHelpers() async throws {
    let entries = try await makeEntries()
    let users = try #require(entries.first { $0.url.contains("v1/users") })
    #expect(users.displayPath == "/v1/users?page=1")
    #expect(users.host == "api.example.com")
    let offline = try #require(entries.first { $0.statusCode == nil })
    #expect(offline.statusText == "ERR")
  }

  @Test func exportTextIncludesEverythingAndRedactsSecrets() async throws {
    let entries = try await makeEntries()
    let login = try #require(entries.first { $0.url.contains("v1/login") })
    let text = login.exportText
    #expect(text.contains("POST https://api.example.com/v1/login"))
    #expect(text.contains("--- Response body ---"))
    #expect(text.contains("curl"))
    #expect(!text.contains("sample-secret-token"))
  }
}

@MainActor
struct ViewModelTests {

  private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
      if condition() { return true }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
  }

  private func client(store: NetworkLogStore) -> APIClient {
    APIClient(baseURL: URL(string: "https://api.example.com")!, transport: MockTransport.stub(), logStore: store)
  }

  @Test func loadsExistingThenStreamsNewEntriesWithoutDuplicates() async throws {
    let store = NetworkLogStore()
    let api = client(store: store)
    try await api.send(Endpoint(path: "one"))
    try await api.send(Endpoint(path: "two"))

    let model = NetworkInspectorViewModel(store: store)
    let running = Task { await model.start() }
    #expect(await waitUntil { model.visibleEntries.count == 2 })

    try await api.send(Endpoint(path: "three"))
    #expect(await waitUntil { model.visibleEntries.count == 3 })
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(model.visibleEntries.count == 3)
    #expect(model.visibleEntries.first?.url.hasSuffix("/three") == true)  // newest first
    running.cancel()
  }

  @Test func clearEmptiesStoreAndList() async throws {
    let store = NetworkLogStore()
    try await client(store: store).send(Endpoint(path: "one"))
    let model = NetworkInspectorViewModel(store: store)
    let running = Task { await model.start() }
    #expect(await waitUntil { model.visibleEntries.count == 1 })

    await model.clear()
    #expect(model.visibleEntries.isEmpty)
    #expect(await store.entries.isEmpty)
    running.cancel()
  }

  @Test func filterAppliesToVisibleEntries() async throws {
    let store = NetworkLogStore()
    let api = client(store: store)
    try await api.send(Endpoint(path: "alpha"))
    try await api.send(Endpoint(path: "beta"))
    let model = NetworkInspectorViewModel(store: store)
    let running = Task { await model.start() }
    #expect(await waitUntil { model.visibleEntries.count == 2 })

    model.filter.query = "beta"
    #expect(model.visibleEntries.count == 1)
    running.cancel()
  }
}
