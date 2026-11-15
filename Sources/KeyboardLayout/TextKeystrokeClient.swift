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
    // Build the table early so the first `strokes` call off the main thread rarely has to wait for it.
    DispatchQueue.main.async { LiveTextKeystrokes.prepare() }
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
/// Text Input Sources calls must run on the main thread, so the table is only ever built there; any
/// thread reads it under `cache`. A call with no table yet off the main thread waits for the main
/// thread to build it (`DispatchQueue.main.sync`, once per process, normally already done by
/// `prepare`), so callers must not hold a lock the main thread may wait for.
enum LiveTextKeystrokes {
  private struct Cached {
    var inputSourceID: String
    var table: TextKeystrokes
  }

  private static let cache = Mutex<Cached?>(nil)

  /// Registers for input source changes once, on first use. The center keeps the observer.
  private static let observeInputSourceChanges: Void = {
    _ = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil,
      queue: .main
    ) { _ in rebuild() }
  }()

  static func strokes(for character: Character) -> [TextStroke]? {
    if cache.withLock({ $0 == nil }) {
      if Thread.isMainThread {
        prepare()
      } else {
        DispatchQueue.main.sync { prepare() }
      }
    }
    return cache.withLock { $0?.table }?.strokes(for: character)
  }

  /// Builds the table unless there already is one. Main thread only.
  static func prepare() {
    dispatchPrecondition(condition: .onQueue(.main))
    observeInputSourceChanges
    if cache.withLock({ $0 == nil }) {
      rebuild()
    }
  }

  /// Rebuilds the table if the input source ID changed. Main thread only.
  private static func rebuild() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let current = KeyboardLayoutData.current() else { return }
    let existingID = cache.withLock { $0?.inputSourceID }
    guard existingID != current.inputSourceID else { return }
    let table = TextKeystrokes(layoutData: current.data, keyboardType: UInt32(LMGetKbdType()))
    cache.withLock { $0 = Cached(inputSourceID: current.inputSourceID, table: table) }
  }
}
