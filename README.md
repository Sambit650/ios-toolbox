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

**Requirements:** iOS 14+ / macOS 12+, Swift 5.9+ (the SwiftUI inspector requires iOS 15+).

## 📦 Installation

### Swift Package Manager (SPM)
1. Open your Xcode project.
2. Go to `File` > `Add Package Dependencies...`
3. Enter the repository URL: `https://github.com/Sambit650/ios-toolbox.git`
4. Select the version or branch you want to install.
5. Add the products you need (`Toolbox`, `ToolboxCore`, `ToolboxNetworking`, `ToolboxDebug`) to your target.

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
│   └── ToolboxDebug         # Network inspector views, view model, filters, previews
└── Tests
    ├── ToolboxCoreTests
    ├── ToolboxNetworkingTests
    └── ToolboxDebugTests
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
