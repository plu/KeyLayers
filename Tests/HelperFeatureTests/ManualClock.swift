import Foundation

/// A clock that moves only when a test advances it. Unlike `TestClock`, a sleep whose deadline is
/// not after `now` returns at once, so advancing before the sleeper got to its sleep can't strand it.
final class ManualClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration

    func advanced(by duration: Duration) -> Instant {
      Instant(offset: offset + duration)
    }

    func duration(to other: Instant) -> Duration {
      other.offset - offset
    }

    static func < (lhs: Instant, rhs: Instant) -> Bool {
      lhs.offset < rhs.offset
    }
  }

  private struct Sleeper {
    var id: UUID
    var deadline: Instant
    var continuation: CheckedContinuation<Void, any Error>
  }

  // Guarded by `lock`.
  private let lock = NSLock()
  private var current = Instant(offset: .zero)
  private var sleepers: [Sleeper] = []
  private var cancelled: Set<UUID> = []

  var now: Instant {
    lock.withLock { current }
  }

  var minimumResolution: Duration {
    .zero
  }

  func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let result: Result<Void, any Error>? = lock.withLock {
          if cancelled.remove(id) != nil {
            return .failure(CancellationError())
          }
          if deadline <= current {
            return .success(())
          }
          sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
          return nil
        }
        if let result {
          continuation.resume(with: result)
        }
      }
    } onCancel: {
      let sleeper = lock.withLock {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
          cancelled.insert(id)
          return Sleeper?.none
        }
        return sleepers.remove(at: index)
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  /// Moves the clock forward and wakes every sleep that is due, earliest first.
  func advance(by duration: Duration) {
    let due = lock.withLock {
      current = current.advanced(by: duration)
      let due = sleepers.filter { $0.deadline <= current }.sorted { $0.deadline < $1.deadline }
      sleepers.removeAll { $0.deadline <= current }
      return due
    }
    for sleeper in due {
      sleeper.continuation.resume()
    }
  }
}
