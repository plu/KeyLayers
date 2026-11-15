import SwiftUI

/// The overlay flashed when a layer is locked or the keymap changes.
public struct LayerHUDView: View {
  public let text: String

  public init(text: String) {
    self.text = text
  }

  public var body: some View {
    Text(text)
      .font(.system(size: 34, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(.horizontal, 32)
      .padding(.vertical, 18)
      .frame(minWidth: 160)
      .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
