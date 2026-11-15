import AppKit
import SwiftUI

/// The menu bar item: a keyboard symbol (dimmed while paused) and, if the settings ask for it,
/// text such as "DEF · Mod".
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
      if isPaused {
        Image(nsImage: Self.dimmedKeyboard)
      } else {
        Image(systemName: "keyboard")
      }
      if !title.isEmpty {
        Text(title)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  /// The keyboard symbol at reduced opacity. The menu bar ignores SwiftUI's opacity and colors on
  /// its label, but keeps a template image's alpha, so this still follows light and dark.
  static let dimmedKeyboard: NSImage = {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard
      let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return NSImage() }
    let image = NSImage(size: symbol.size, flipped: false) { rect in
      symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmedOpacity)
      return true
    }
    image.isTemplate = true
    return image
  }()

  static let pointSize: CGFloat = 13
  static let dimmedOpacity: CGFloat = 0.4
}
