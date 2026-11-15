# ios-toolbox

## Overview

A modular Swift package of utilities for iOS development: core String/Date helpers, a resilient networking layer, and an in-app network inspector. Import only the modules you need.

## Table of Contents
- [Modules](#-modules)
- [Installation](#-installation)
- [Usage](#-usage)
- [Project Structure](#-project-structure)
- [Contributing](#-contributing)
- [Contact](#-contact)

## 🧩 Modules

The package is split into small modules. Import only what you need, or `import Toolbox` for everything.

| Module | Description | Depends on |
| --- | --- | --- |
| `Toolbox` | Umbrella module that re-exports all modules below | all |
| `ToolboxCore` | `String` and `Date` extensions, plus `StringUtils` | – |
| `ToolboxNetworking` | Async/await `APIClient` with interceptors, retry/backoff, 401 refresh-and-replay, request de-duplication, response caching and traffic logging | – |
| `ToolboxDebug` | SwiftUI network inspector, shake gesture helper and log filtering | `ToolboxNetworking` |
| `ToolboxFeatureFlags` | Typed Bool/Int/String feature flags with layered providers (local, JSON, remote with disk cache), environments, user targeting and SwiftUI/Combine bindings | `ToolboxNetworking` |

**Requirements:** iOS 14+ / macOS 12+, Swift 5.9+ (the SwiftUI inspector requires iOS 15+).

## 📦 Installation

### Swift Package Manager (SPM)
1. Open your Xcode project.
2. Go to `File` > `Add Package Dependencies...`
3. Enter the repository URL: `https://github.com/Sambit650/ios-toolbox.git`
4. Select the version or branch you want to install.
5. Add the products you need (`Toolbox`, `ToolboxCore`, `ToolboxNetworking`, `ToolboxDebug`, `ToolboxFeatureFlags`) to your target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/Sambit650/ios-toolbox.git", branch: "main")
// then, in your target:
.product(name: "Toolbox", package: "ios-toolbox")
```

## 🔨 Usage

### ToolboxCore

```swift
import ToolboxCore

Date().formatted("yyyy-MM-dd")        // "2026-11-15"
Date().isToday                        // true
Date().adding(.day, value: 3).dayOfWeek()
Date().startOfDay / Date().endOfDay

"  ".isEmptyOrWhitespace()            // true
"12345".containsOnlyDigits()          // true
"Passw0rd!".containsSpecialCharacters()
StringUtils.trimWhitespace("  hi  ")  // "hi"
```

### ToolboxNetworking

```swift
import ToolboxNetworking

let logs = NetworkLogStore()
let client = APIClient(
    baseURL: URL(string: "https://api.example.com")!,
    interceptors: [BearerTokenInterceptor { await session.accessToken }],
    authRefresher: { try await session.refreshTokens() },
    logStore: logs)

let user: User = try await client.send(
    Endpoint(path: "users/42", cachePolicy: .cacheFirst(ttl: 60)))

let created: User = try await client.send(
    .json(path: "users", body: NewUser(name: "Sam")))
```

Highlights: `RetryPolicy` (exponential backoff, jitter, `Retry-After`), `CachePolicy` (`.networkOnly`, `.cacheFirst`, `.refresh`), `StaticHeadersInterceptor`, cURL export via `URLRequest`, and `MockTransport` for tests.

### ToolboxDebug

```swift
import ToolboxDebug

struct RootView: View {
    @State private var showInspector = false
    let logs: NetworkLogStore

    var body: some View {
        ContentView()
            .onShake { showInspector = true }
            .networkInspector(store: logs, isPresented: $showInspector)
    }
}
```

The inspector lists captured requests, supports search and status filtering, shows request/response details with formatted bodies, and copies cURL commands. Sensitive headers (`Authorization`, `Cookie`, ...) are redacted by default.

### ToolboxFeatureFlags

```swift
import ToolboxFeatureFlags

extension FlagKey where Value == Bool {
    static let newCheckout = FlagKey("new_checkout", default: false)
    static let premiumBanner = FlagKey("premium_banner", default: false)
}

// Earlier providers win: put remote/cached values before bundled defaults.
let flags = FeatureFlags(
    providers: [
        UserDefaultsFlagProvider(),                              // persisted local toggles
        try JSONFlagProvider(fileURL: bundledFlagsURL, environment: .staging),
    ],
    environment: .staging,
    context: FlagContext(attributes: ["isPremium": .bool(user.isPremium)]))

flags[.newCheckout]                       // typed read
flags.setOverride(true, for: .newCheckout) // runtime override, e.g. from a debug menu

// SwiftUI
struct CheckoutView: View {
    @FeatureFlag(.newCheckout, flags: appFlags) var useNewCheckout
    var body: some View { useNewCheckout ? NewCheckout() : OldCheckout() }
}

// UIKit / Combine
flags.publisher(for: .newCheckout).sink { enabled in /* update UI */ }.store(in: &bag)
```

JSON flags may use per-environment sections and targeting rules:

```json
{
  "default": { "new_checkout": false },
  "staging": { "new_checkout": true },
  "production": {
    "premium_banner": { "value": false,
      "rules": [{ "attribute": "isPremium", "equals": true, "value": true }] }
  }
}
```

#### Remote flags

`RemoteFlagProvider` fetches the same JSON from your backend (or a static file on a CDN) through an `APIClient`. Reads stay synchronous and come from memory; the last good response is cached on disk, so flags work offline and at launch. A failed or invalid fetch never discards existing values.

```swift
let remote = RemoteFlagProvider(
    client: apiClient,
    endpoint: Endpoint(path: "flags"),
    environment: .staging,
    refreshInterval: 15 * 60)          // minimum gap between non-forced refreshes

let flags = FeatureFlags(providers: [remote, bundled])   // remote wins, bundled is the fallback
await flags.refresh(remote)            // at launch / when the app becomes active; updates views on change
await flags.refresh(remote, force: true)
```

To use Firebase Remote Config, LaunchDarkly or another SDK, implement `FlagProvider` yourself and call `flags.reload()` when new values arrive.

## 🗂 Project Structure

```
ios-toolbox
├── Package.swift
├── Sources
│   ├── Toolbox              # Umbrella (re-exports all modules)
│   ├── ToolboxCore
│   │   ├── Date             # Date+Extension
│   │   └── String           # String extensions, validation, StringUtils
│   ├── ToolboxNetworking    # APIClient, Endpoint, RetryPolicy, ResponseCache,
│   │                        # interceptors, auth refresh, NetworkLogStore, ...
│   ├── ToolboxDebug         # Network inspector views, view model, filters, previews
│   └── ToolboxFeatureFlags  # FlagKey, FeatureFlags, providers, SwiftUI/Combine bindings
└── Tests
    ├── ToolboxCoreTests
    ├── ToolboxNetworkingTests
    ├── ToolboxDebugTests
    └── ToolboxFeatureFlagsTests
```

Run the tests with `swift test`.

## 🤝 Contributing

We welcome contributions from developers of all experience levels. To contribute, please follow these steps:

1. Fork this repository.
2. Create a new branch for your changes (`git checkout -b feature-name`).
3. Make your changes and commit them (`git commit -m 'Add feature'`).
4. Push to your forked repository (`git push origin feature-name`).
5. Open a pull request to the `main` branch of this repository.

### Code Style
- Follow Swift best practices for code style and formatting.
- Write clear, concise commit messages.
- Add unit tests for new functionality where applicable.

### Issues and Bugs
If you encounter any issues or bugs, please report them via the [Issues](https://github.com/Sambit650/ios-toolbox/issues) page. Make sure to include relevant details such as:
- iOS version
- Device type
- Steps to reproduce the issue

## 📬 Contact

For any questions or feedback, feel free to open an issue or contact the repository maintainers via email:

- **Maintainer**: Sambit
- **Email**: sambit650@gmail.com

*Built with ❤️, for developers!*
