//
//  NetworkInspectorView.swift
//  ToolboxDebug
//

import SwiftUI
import ToolboxNetworking

// MARK: - List

/// A full-screen network inspector: live request list, search, status filter, and per-request detail.
///
/// ```swift
/// .sheet(isPresented: $showInspector) { NetworkInspectorView(store: logs) }
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct NetworkInspectorView: View {
  @StateObject private var model: NetworkInspectorViewModel
  @Environment(\.dismiss) private var dismiss

  public init(store: NetworkLogStore) {
    _model = StateObject(wrappedValue: NetworkInspectorViewModel(store: store))
  }

  public var body: some View {
    NavigationView {
      content
        .navigationTitle("Network")
        .searchable(text: $model.filter.query, prompt: "URL, method, status, body")
        .toolbar { toolbarContent }
    }
    #if os(iOS)
    .navigationViewStyle(.stack)
    #endif
    .task { await model.start() }
  }

  @ViewBuilder private var content: some View {
    let rows = model.visibleEntries
    if rows.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "antenna.radiowaves.left.and.right.slash")
          .font(.largeTitle)
          .foregroundColor(.secondary)
        Text(model.filter.isActive ? "No matching requests" : "No requests yet")
          .font(.headline)
        Text(model.filter.isActive ? "Try clearing the search or filter." : "Network traffic will appear here as it happens.")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(rows) { entry in
        NavigationLink(destination: NetworkLogDetailView(entry: entry)) {
          NetworkLogRow(entry: entry)
        }
      }
      #if os(iOS)
      .listStyle(.plain)
      #endif
    }
  }

  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Picker("Filter", selection: $model.filter.status) {
          ForEach(NetworkLogFilter.Status.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        Button(role: .destructive) {
          Task { await model.clear() }
        } label: {
          Label("Clear Log", systemImage: "trash")
        }
      } label: {
        Image(systemName: model.filter.status == .all
          ? "line.3.horizontal.decrease.circle"
          : "line.3.horizontal.decrease.circle.fill")
      }
    }
    ToolbarItem(placement: .cancellationAction) {
      Button("Done") { dismiss() }
    }
  }
}

// MARK: - Row

@available(iOS 15.0, macOS 12.0, *)
struct NetworkLogRow: View {
  let entry: NetworkLogEntry

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(entry.statusText)
        .font(.system(.caption, design: .monospaced).weight(.bold))
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(entry.category.color)
        .cornerRadius(5)
        .frame(minWidth: 44)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(entry.method).font(.caption.weight(.semibold)).foregroundColor(.secondary)
          Text(entry.displayPath).font(.subheadline).lineLimit(2)
        }
        HStack(spacing: 6) {
          Text(entry.host)
          Text("·")
          Text(entry.durationText)
          Text("·")
          Text(entry.startedAt, style: .time)
          if entry.fromCache { Tag(text: "CACHE", color: .blue) }
          if entry.attempt > 1 { Tag(text: "RETRY \(entry.attempt)", color: .orange) }
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 2)
  }
}

@available(iOS 15.0, macOS 12.0, *)
private struct Tag: View {
  let text: String
  let color: Color
  var body: some View {
    Text(text)
      .font(.system(size: 9, weight: .bold))
      .foregroundColor(color)
      .padding(.horizontal, 4)
      .padding(.vertical, 1)
      .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1))
  }
}

extension StatusCategory {
  var color: Color {
    switch self {
    case .success: return .green
    case .redirect: return .blue
    case .clientError: return .orange
    case .serverError, .failure: return .red
    }
  }
}
