import Foundation
import KeyboardLayout
import KeymapModel
import RemapEngine

/// One thing a running macro does: post a key event or wait.
enum MacroAction: Equatable, Sendable {
  case event(OutputEvent)
  case wait(Duration)
}

/// Expands macro steps into the events and waits that perform them.
enum MacroScript {
  private static let maxDelay = Duration.milliseconds(60000)

  static func actions(for step: MacroStep, strokes: (Character) -> [TextStroke]?) -> [MacroAction] {
    switch step {
    case let .key(keyStep):
      keyActions(keyStep)
    case let .text(text):
      text.flatMap { character -> [MacroAction] in
        (strokes(character) ?? []).flatMap { tap($0.key, $0.modifiers) }
      }
    case let .delay(milliseconds):
      [.wait(min(max(.milliseconds(milliseconds), .zero), maxDelay))]
    case .unsupported:
      []
    }
  }

  /// Text steps type the characters of the keyboard layout with Caps Lock off.
  static func needsCapsLockOff(_ step: MacroStep) -> Bool {
    if case let .text(text) = step {
      return !text.isEmpty
    }
    return false
  }

  private static func keyActions(_ step: KeyStep) -> [MacroAction] {
    var modifiers = step.modifiers
    var key = step.key
    if let modifier = key?.modifier {
      modifiers.insert(Modifiers(modifier))
      key = nil
    }
    guard let key else {
      let keys = modifiers.members.map(\.keyID)
      switch step.kind {
      case .tap: return keys.map { event($0, true) } + keys.reversed().map { event($0, false) }
      case .press: return keys.map { event($0, true) }
      case .release: return keys.reversed().map { event($0, false) }
      }
    }
    switch step.kind {
    case .tap: return tap(key, modifiers)
    case .press: return [event(key, true, modifiers)]
    case .release: return [event(key, false, modifiers)]
    }
  }

  private static func tap(_ key: KeyID, _ modifiers: Modifiers) -> [MacroAction] {
    [event(key, true, modifiers), event(key, false, modifiers)]
  }

  private static func event(_ key: KeyID, _ isDown: Bool, _ modifiers: Modifiers = []) -> MacroAction {
    .event(OutputEvent(key: key, isDown: isDown, modifiers: modifiers))
  }
}
