//
//  NetworkInspectorPreviews.swift
//  ToolboxDebug
//

#if DEBUG
import SwiftUI
import ToolboxNetworking

@available(iOS 15.0, macOS 12.0, *)
private struct InspectorPreviewHost: View {
  @State private var store: NetworkLogStore?

  var body: some View {
    Group {
      if let store { NetworkInspectorView(store: store) } else { ProgressView() }
    }
    .task { store = await NetworkLogStore.sample() }
  }
}

@available(iOS 15.0, macOS 12.0, *)
struct NetworkInspectorView_Previews: PreviewProvider {
  static var previews: some View {
    InspectorPreviewHost()
    InspectorPreviewHost().preferredColorScheme(.dark)
  }
}
#endif
