//
//  NetworkLogDetailView.swift
//  ToolboxDebug
//

import SwiftUI
import ToolboxNetworking

/// Everything about one request: overview, headers, bodies, and copy actions.
@available(iOS 15.0, macOS 12.0, *)
public struct NetworkLogDetailView: View {
  let entry: NetworkLogEntry
  @State private var copiedLabel: String?

  public init(entry: NetworkLogEntry) {
    self.entry = entry
  }

  public var body: some View {
    List {
      Section("Overview") {
        row("URL", entry.url)
        row("Method", entry.method)
        row("Status", entry.statusText + (entry.fromCache ? " (cache)" : ""))
        row("Duration", entry.durationText)
        row("Started", entry.startedAt.formatted(date: .abbreviated, time: .standard))
        if entry.attempt > 1 { row("Attempt", "\(entry.attempt)") }
        if let error = entry.errorDescription { row("Error", error) }
      }

      Section("Actions") {
        copyButton("Copy cURL", systemImage: "terminal", text: entry.curl)
        copyButton("Copy URL", systemImage: "link", text: entry.url)
        if let body = BodyFormatter.format(entry.responseBody) {
          copyButton("Copy Response Body", systemImage: "doc.on.doc", text: body)
        }
        copyButton("Copy Everything", systemImage: "square.and.arrow.up", text: entry.exportText)
      }

      headersSection("Request Headers", entry.requestHeaders)
      bodySection("Request Body", entry.requestBody)
      headersSection("Response Headers", entry.responseHeaders)
      bodySection("Response Body", entry.responseBody)
    }
    .navigationTitle(entry.displayPath)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .overlay(alignment: .bottom) {
      if let copiedLabel {
        Label(copiedLabel, systemImage: "checkmark.circle.fill")
          .font(.subheadline.weight(.medium))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(.bottom, 20)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }

  private func row(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption).foregroundColor(.secondary)
      Text(value).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
    }
  }

  private func copyButton(_ title: String, systemImage: String, text: String) -> some View {
    Button {
      Clipboard.copy(text)
      withAnimation { copiedLabel = "\(title.replacingOccurrences(of: "Copy ", with: "")) copied" }
      Task {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        withAnimation { copiedLabel = nil }
      }
    } label: {
      Label(title, systemImage: systemImage)
    }
  }

  @ViewBuilder private func headersSection(_ title: String, _ headers: [String: String]) -> some View {
    Section(title) {
      if headers.isEmpty {
        Text("None").foregroundColor(.secondary)
      } else {
        ForEach(headers.sorted { $0.key < $1.key }, id: \.key) { row($0.key, $0.value) }
      }
    }
  }

  @ViewBuilder private func bodySection(_ title: String, _ data: Data?) -> some View {
    Section(title) {
      if let text = BodyFormatter.format(data) {
        Text(text)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
      } else {
        Text("Empty").foregroundColor(.secondary)
      }
    }
  }
}
