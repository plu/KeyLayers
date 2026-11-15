import Carbon
import CoreGraphics
import Dependencies
import DependenciesMacros
import Foundation
import Synchronization

/// Key presses that type text with the current input source.
@DependencyClient
public struct TextKeystrokeClient: Sendable {
  /// The strokes that type `character` with Caps Lock off, or nil when the layout cannot type it.
  public var strokes: @Sendable (_ character: Character) -> [TextStroke]? = { _ in nil }
  /// Whether Caps Lock is currently on.
  public var capsLockIsOn: @Sendable () -> Bool = { false }
  /// Brings the table up to date on the main actor: builds it if there is none, rebuilds it if the
  /// selected input source changed. Never blocks the caller's thread.
  public var refresh: @Sendable () async -> Void = {}
}

extension TextKeystrokeClient: DependencyKey {
  public static let liveValue: TextKeystrokeClient = {
    // Warm up: `strokes` returns nil until the first table exists.
    LiveTextKeystrokes.scheduleBuild()
    return TextKeystrokeClient(
      strokes: { LiveTextKeystrokes.strokes(for: $0) },
      capsLockIsOn: { CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift) },
      refresh: { await MainActor.run { LiveTextKeystrokes.refresh() } }
    )
  }()

  public static let testValue = TextKeystrokeClient()

  public static let previewValue: TextKeystrokeClient = {
    let us = KeyboardLayoutData.layoutData(inputSourceID: "com.apple.keylayout.US")
      .map { TextKeystrokes(layoutData: $0, keyboardType: UInt32(LMGetKbdType())) }
    return TextKeystrokeClient(strokes: { us?.strokes(for: $0) }, capsLockIsOn: { false }, refresh: {})
  }()
}

public extension DependencyValues {
  var textKeystrokes: TextKeystrokeClient {
    get { self[TextKeystrokeClient.self] }
    set { self[TextKeystrokeClient.self] = newValue }
  }
}

/// The current input source's table, rebuilt when the selected input source changes to one with a
/// different ID.
///
/// Text Input Sources calls must run on the main thread, so the table is only ever built there, and
/// any thread reads it under `state`. With no table yet, `strokes` builds it right away on the main
/// thread; any other thread never blocks: it schedules one asynchronous build on the main queue (at
/// most one pending) and gets nil, so background callers may get nil until the warm-up scheduled when
/// `liveValue` is created has completed.
///
/// Input source changes are observed with `.deliverImmediately`: the helper is an agent app that is
/// almost never active, and an inactive app's distributed notifications are otherwise held back.
enum LiveTextKeystrokes {
  private struct Cached {
    var inputSourceID: String
    var table: TextKeystrokes
  }

  private struct State {
    var cached: Cached?
    var buildScheduled = false
  }

  private static let state = Mutex(State())

  /// Receives input source changes. Distributed notification centers don't retain observers.
  private final class InputSourceObserver: NSObject, @unchecked Sendable {
    @objc func inputSourceChanged(_: Notification) {
      DispatchQueue.main.async { LiveTextKeystrokes.refresh() }
    }
  }

  private static let observer = InputSourceObserver()

  /// Registers for input source changes once, on first use.
  private static let observeInputSourceChanges: Void = {
    DistributedNotificationCenter.default().addObserver(
      observer,
      selector: #selector(InputSourceObserver.inputSourceChanged(_:)),
      name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
  }()

  /// The strokes for `character` from the cached table; nil off the main thread while there is no
  /// table yet.
  static func strokes(for character: Character) -> [TextStroke]? {
    if let table = state.withLock({ $0.cached?.table }) {
      return table.strokes(for: character)
    }
    guard Thread.isMainThread else {
      scheduleBuild()
      return nil
    }
    refresh()
    return state.withLock { $0.cached?.table }?.strokes(for: character)
  }

  /// Schedules a build on the main queue unless a table exists or a build is already pending.
  static func scheduleBuild() {
    let schedule = state.withLock { state in
      guard state.cached == nil, !state.buildScheduled else { return false }
      state.buildScheduled = true
      return true
    }
    guard schedule else { return }
    DispatchQueue.main.async {
      refresh()
      state.withLock { $0.buildScheduled = false }
    }
  }

  /// Builds the table if there is none or the selected input source's ID changed, and starts
  /// observing input source changes. Main thread only.
  static func refresh() {
    precondition(Thread.isMainThread, "Text Input Sources must be called on the main thread")
    observeInputSourceChanges
    guard let current = KeyboardLayoutData.current() else { return }
    let existingID = state.withLock { $0.cached?.inputSourceID }
    guard existingID != current.inputSourceID else { return }
    let table = TextKeystrokes(layoutData: current.data, keyboardType: UInt32(LMGetKbdType()))
    state.withLock { $0.cached = Cached(inputSourceID: current.inputSourceID, table: table) }
  }

  /// Forgets the table, as if nothing had asked for it yet. For tests.
  static func reset() {
    state.withLock { $0 = State() }
  }
}
