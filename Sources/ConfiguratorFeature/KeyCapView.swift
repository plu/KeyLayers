import SwiftUI

/// One key cap: the action's primary text, its badge underneath, styled per `KeyCapContent.Style`.
struct KeyCapView: View {
  let content: KeyCapContent
  let shape: KeyCapShape
  /// Points per key unit; text sizes follow it.
  let unit: CGFloat

  var body: some View {
    ZStack {
      shape.fill(background)
      shape.stroke(border, style: StrokeStyle(lineWidth: 1, dash: content.style == .inherited ? [3, 2] : []))
      VStack(spacing: unit * 0.04) {
        Text(content.primary)
          .font(.system(size: unit * 0.3, weight: .medium))
          .foregroundStyle(foreground)
        if let badge = content.badge {
          Text(badge)
            .font(.system(size: unit * 0.17, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, unit * 0.06)
            .background(.quaternary, in: Capsule())
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.4)
      .padding(.horizontal, unit * 0.06)
      // On a tall Return the text sits in the upper part.
      .frame(maxWidth: .infinity, maxHeight: shape.upperHeight ?? .infinity)
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private var foreground: AnyShapeStyle {
    switch content.style {
    case .normal, .unmapped: AnyShapeStyle(.primary)
    case .inherited: AnyShapeStyle(.tertiary)
    case .blocked: AnyShapeStyle(Color.red)
    case .unsupported: AnyShapeStyle(Color.orange)
    }
  }

  private var background: AnyShapeStyle {
    switch content.style {
    case .normal: AnyShapeStyle(Color.accentColor.opacity(0.18))
    case .unmapped: AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    case .inherited: AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    case .blocked: AnyShapeStyle(Color.red.opacity(0.12))
    case .unsupported: AnyShapeStyle(Color.orange.opacity(0.15))
    }
  }

  private var border: AnyShapeStyle {
    switch content.style {
    case .normal: AnyShapeStyle(Color.accentColor.opacity(0.6))
    case .unmapped, .inherited: AnyShapeStyle(Color(nsColor: .separatorColor))
    case .blocked: AnyShapeStyle(Color.red.opacity(0.5))
    case .unsupported: AnyShapeStyle(Color.orange.opacity(0.6))
    }
  }
}

/// A key cap's outline: a rounded rectangle, or the tall ISO/JIS Return, whose lower part is
/// right-aligned and `notch` points narrower than its upper part.
struct KeyCapShape: Shape {
  var cornerRadius: CGFloat
  /// For the ISO Return: the height of the upper part and how much narrower the lower part is.
  var isoEnter: (upperHeight: CGFloat, notch: CGFloat)?

  var upperHeight: CGFloat? {
    isoEnter?.upperHeight
  }

  func path(in rect: CGRect) -> Path {
    guard let (upperHeight, notch) = isoEnter else {
      return Path(roundedRect: rect, cornerRadius: cornerRadius)
    }
    let corners = [
      CGPoint(x: rect.minX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY),
      CGPoint(x: rect.minX + notch, y: rect.maxY),
      CGPoint(x: rect.minX + notch, y: rect.minY + upperHeight),
      CGPoint(x: rect.minX, y: rect.minY + upperHeight),
    ]
    var path = Path()
    // Start halfway along the last edge so every corner is rounded the same way.
    let start = CGPoint(x: rect.minX, y: rect.minY + upperHeight / 2)
    path.move(to: start)
    for index in corners.indices {
      let next = corners[(index + 1) % corners.count]
      path.addArc(tangent1End: corners[index], tangent2End: next, radius: cornerRadius)
    }
    path.closeSubpath()
    return path
  }
}
