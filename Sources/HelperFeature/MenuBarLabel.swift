import SwiftUI

/// The menu bar item: a keyboard symbol (with a badge while paused) and "DEF · Mod".
public struct MenuBarLabel: View {
  public let title: String
  public let isPaused: Bool

  public init(title: String, isPaused: Bool) {
    self.title = title
    self.isPaused = isPaused
  }

  public var body: some View {
    HStack(spacing: 4) {
      Image(systemName: isPaused ? "keyboard.badge.ellipsis" : "keyboard")
      Text(title)
    }
    .accessibilityElement(children: .combine)
  }
}
