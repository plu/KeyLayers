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
}

extension TextKeystrokeClient: DependencyKey {
  public static let liveValue: TextKeystrokeClient = {
    // Warm up: `strokes` returns nil until the first table exists.
    LiveTextKeystrokes.scheduleBuild()
    return TextKeystrokeClient(
      strokes: { LiveTextKeystrokes.strokes(for: $0) },
      capsLockIsOn: { CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift) }
    )
  }()

  public static let testValue = TextKeystrokeClient()

  public static let previewValue: TextKeystrokeClient = {
    let us = KeyboardLayoutData.layoutData(inputSourceID: "com.apple.keylayout.US")
      .map { TextKeystrokes(layoutData: $0, keyboardType: UInt32(LMGetKbdType())) }
    return TextKeystrokeClient(strokes: { us?.strokes(for: $0) }, capsLockIsOn: { false })
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
/// any thread reads it under `state`. `strokes` never blocks: with no table yet it schedules one
/// asynchronous build on the main queue (at most one pending) and returns nil, so callers may get nil
/// until the warm-up scheduled when `liveValue` is created has completed.
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

  /// Registers for input source changes once, on first use. The center keeps the observer.
  private static let observeInputSourceChanges: Void = {
    _ = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil,
      queue: .main
    ) { _ in rebuild() }
  }()

  /// The strokes for `character` from the cached table; nil while there is no table yet.
  static func strokes(for character: Character) -> [TextStroke]? {
    guard let table = state.withLock({ $0.cached?.table }) else {
      scheduleBuild()
      return nil
    }
    return table.strokes(for: character)
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
      observeInputSourceChanges
      rebuild()
      state.withLock { $0.buildScheduled = false }
    }
  }

  /// Rebuilds the table if the input source ID changed. Main thread only.
  private static func rebuild() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let current = KeyboardLayoutData.current() else { return }
    let existingID = state.withLock { $0.cached?.inputSourceID }
    guard existingID != current.inputSourceID else { return }
    let table = TextKeystrokes(layoutData: current.data, keyboardType: UInt32(LMGetKbdType()))
    state.withLock { $0.cached = Cached(inputSourceID: current.inputSourceID, table: table) }
  }
}
