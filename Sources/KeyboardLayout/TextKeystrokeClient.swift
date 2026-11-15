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
  public static let liveValue = TextKeystrokeClient(
    strokes: { LiveTextKeystrokes.strokes(for: $0) },
    capsLockIsOn: { CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift) }
  )

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

/// The current input source's table, built on first use and rebuilt when the selected input source
/// changes to one with a different ID.
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
      queue: nil
    ) { _ in rebuild() }
  }()

  static func strokes(for character: Character) -> [TextStroke]? {
    observeInputSourceChanges
    let table = cache.withLock { cached in
      if cached == nil {
        cached = build(replacing: nil)
      }
      return cached?.table
    }
    return table?.strokes(for: character)
  }

  private static func rebuild() {
    cache.withLock { $0 = build(replacing: $0) }
  }

  /// A table for the current input source, reusing `existing` when the input source ID is unchanged.
  private static func build(replacing existing: Cached?) -> Cached? {
    guard let current = KeyboardLayoutData.current() else { return nil }
    if let existing, existing.inputSourceID == current.inputSourceID {
      return existing
    }
    let table = TextKeystrokes(layoutData: current.data, keyboardType: UInt32(LMGetKbdType()))
    return Cached(inputSourceID: current.inputSourceID, table: table)
  }
}
