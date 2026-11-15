//
//  NetworkError.swift
//  ToolboxNetworking
//

import Foundation

/// Errors thrown by ``APIClient``.
public enum NetworkError: Error {
  /// The endpoint could not be turned into a valid URL.
  case invalidURL
  /// The response was not an HTTP response.
  case nonHTTPResponse
  /// The server answered with a non-2xx status code.
  case httpStatus(code: Int, data: Data, headers: [String: String])
  /// The response body could not be decoded.
  case decoding(Error)
  /// The request could not be encoded.
  case encoding(Error)
  /// The auth refresh closure threw while handling a 401.
  case tokenRefreshFailed(Error)
  /// The underlying transport failed (offline, timeout, ...).
  case transport(Error)
}

extension NetworkError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidURL: return "The request URL is invalid."
    case .nonHTTPResponse: return "The server returned a non-HTTP response."
    case let .httpStatus(code, _, _): return "The server responded with status \(code)."
    case let .decoding(error): return "Failed to decode response: \(error.localizedDescription)"
    case let .encoding(error): return "Failed to encode request: \(error.localizedDescription)"
    case let .tokenRefreshFailed(error): return "Failed to refresh credentials: \(error.localizedDescription)"
    case let .transport(error): return error.localizedDescription
    }
  }
}

public extension NetworkError {
  /// HTTP status code, when the error came from a non-2xx response.
  var statusCode: Int? {
    if case let .httpStatus(code, _, _) = self { return code }
    return nil
  }

  /// Seconds to wait as requested by the server's `Retry-After` header
  /// (either delta-seconds or an HTTP date), if present on an HTTP error.
  func retryAfter(now: Date = Date()) -> TimeInterval? {
    guard case let .httpStatus(_, _, headers) = self,
      let raw = headers.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })?
        .value.trimmingCharacters(in: .whitespaces)
    else { return nil }

    if let seconds = TimeInterval(raw) { return max(0, seconds) }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: raw).map { max(0, $0.timeIntervalSince(now)) }
  }
}

extension HTTPURLResponse {
  /// Header fields as a plain `[String: String]`.
  var stringHeaders: [String: String] {
    allHeaderFields.reduce(into: [:]) { result, pair in
      if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
    }
  }
}
