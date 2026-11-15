import SwiftUI

/// The menu bar item: a keyboard symbol (with a badge while paused) and, if the settings ask for
/// it, text such as "DEF · Mod".
public struct MenuBarLabel: View {
  public let title: String
  public let accessibilityLabel: String
  public let isPaused: Bool

  public init(title: String, accessibilityLabel: String, isPaused: Bool) {
    self.title = title
    self.accessibilityLabel = accessibilityLabel
    self.isPaused = isPaused
  }

  public var body: some View {
    HStack(spacing: 4) {
      Image(systemName: isPaused ? "keyboard.badge.ellipsis" : "keyboard")
      if !title.isEmpty {
        Text(title)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }
}
