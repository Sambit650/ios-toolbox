//
//  InspectorPresentation.swift
//  ToolboxDebug
//

import SwiftUI
import ToolboxNetworking

@available(iOS 15.0, macOS 12.0, *)
public extension View {
  /// Presents the network inspector as a sheet.
  func networkInspector(store: NetworkLogStore, isPresented: Binding<Bool>) -> some View {
    sheet(isPresented: isPresented) { NetworkInspectorView(store: store) }
  }
}

#if canImport(UIKit)
import UIKit

extension Notification.Name {
  /// Posted by `ShakeWindow` whenever the user shakes the device.
  static let toolboxDeviceDidShake = Notification.Name("ToolboxDebug.deviceDidShake")
}

extension UIWindow {
  // Observing shakes at window level works regardless of which view is focused.
  open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    super.motionEnded(motion, with: event)
    if motion == .motionShake {
      NotificationCenter.default.post(name: .toolboxDeviceDidShake, object: nil)
    }
  }
}

@available(iOS 15.0, *)
public extension View {
  /// Runs `action` whenever the device is shaken (also works in the Simulator via Device ▸ Shake).
  func onShake(perform action: @escaping () -> Void) -> some View {
    onReceive(NotificationCenter.default.publisher(for: .toolboxDeviceDidShake)) { _ in action() }
  }

  /// Opens the network inspector when the device is shaken.
  ///
  /// Wrap it in `#if DEBUG` so it never ships to users:
  /// ```swift
  /// #if DEBUG
  /// ContentView().inspectNetworkOnShake(store: logs)
  /// #endif
  /// ```
  func inspectNetworkOnShake(store: NetworkLogStore) -> some View {
    modifier(InspectOnShake(store: store))
  }
}

@available(iOS 15.0, *)
private struct InspectOnShake: ViewModifier {
  let store: NetworkLogStore
  @State private var isPresented = false

  func body(content: Content) -> some View {
    content
      .onShake { isPresented = true }
      .networkInspector(store: store, isPresented: $isPresented)
  }
}
#endif
