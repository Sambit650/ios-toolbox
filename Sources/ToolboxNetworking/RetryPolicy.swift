//
//  RetryPolicy.swift
//  ToolboxNetworking
//

import Foundation

/// Controls automatic retries with exponential backoff and jitter.
public struct RetryPolicy: Sendable {
  /// Total attempts including the first one. `1` disables retrying.
  public var maxAttempts: Int
  public var baseDelay: TimeInterval
  public var maxDelay: TimeInterval
  /// Applies "full jitter": the delay is random in `0...exponentialDelay`.
  public var usesJitter: Bool
  public var retryableStatusCodes: Set<Int>
  /// Honour the server's `Retry-After` header (waits at least that long).
  public var respectsRetryAfter: Bool
  /// If the server asks for a longer wait than this, give up instead of retrying.
  public var maxRetryAfter: TimeInterval
  /// When `false` (default) non-idempotent methods such as POST are never retried.
  public var retriesNonIdempotentMethods: Bool

  public init(
    maxAttempts: Int = 3,
    baseDelay: TimeInterval = 0.5,
    maxDelay: TimeInterval = 30,
    usesJitter: Bool = true,
    retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
    retriesNonIdempotentMethods: Bool = false,
    respectsRetryAfter: Bool = true,
    maxRetryAfter: TimeInterval = 60
  ) {
    self.maxAttempts = max(1, maxAttempts)
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
    self.usesJitter = usesJitter
    self.retryableStatusCodes = retryableStatusCodes
    self.retriesNonIdempotentMethods = retriesNonIdempotentMethods
    self.respectsRetryAfter = respectsRetryAfter
    self.maxRetryAfter = maxRetryAfter
  }

  public static let none = RetryPolicy(maxAttempts: 1)
  public static let `default` = RetryPolicy()

  /// Delay before the retry that follows `attempt` (1-based).
  /// - Parameter randomFactor: A value in `0...1`; injectable for deterministic tests.
  public func delay(afterAttempt attempt: Int, randomFactor: Double = .random(in: 0...1)) -> TimeInterval {
    let exponential = min(maxDelay, baseDelay * pow(2, Double(max(0, attempt - 1))))
    return usesJitter ? exponential * randomFactor : exponential
  }

  /// Backoff delay, raised to the server's `Retry-After` when present.
  func retryDelay(
    afterAttempt attempt: Int, error: NetworkError,
    now: Date = Date(), randomFactor: Double = .random(in: 0...1)
  ) -> TimeInterval {
    let backoff = delay(afterAttempt: attempt, randomFactor: randomFactor)
    guard respectsRetryAfter, let requested = error.retryAfter(now: now) else { return backoff }
    return max(backoff, requested)
  }

  func shouldRetry(error: NetworkError, method: HTTPMethod, attempt: Int, now: Date = Date()) -> Bool {
    guard attempt < maxAttempts else { return false }
    guard method.isIdempotent || retriesNonIdempotentMethods else { return false }

    switch error {
    case let .httpStatus(code, _, _):
      guard retryableStatusCodes.contains(code) else { return false }
      if respectsRetryAfter, let requested = error.retryAfter(now: now), requested > maxRetryAfter {
        return false
      }
      return true
    case let .transport(underlying):
      guard let urlError = underlying as? URLError else { return false }
      return Self.transientURLErrors.contains(urlError.code)
    default:
      return false
    }
  }

  private static let transientURLErrors: Set<URLError.Code> = [
    .timedOut, .networkConnectionLost, .notConnectedToInternet,
    .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost,
  ]
}
