import KeymapModel
import SwiftUI

/// The scrolling key list of a key picker, with section headers for grouped keys. Tapping the
/// selected key deselects it.
struct KeyPickerList: View {
  let results: [KeySearchResult]
  let selection: KeyID?
  /// Prefixes the rows' accessibility identifiers (`<prefix>.result.<key>`).
  let identifierPrefix: String
  let select: (KeyID?) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
            if let group = result.group, index == 0 || results[index - 1].group != group {
              Text(group)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
            row(result)
          }
        }
      }
      .frame(maxHeight: .infinity)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
      .onAppear {
        if let selection {
          proxy.scrollTo(selection, anchor: .center)
        }
      }
    }
  }

  private func row(_ result: KeySearchResult) -> some View {
    let isSelected = result.key == selection
    return Button {
      select(isSelected ? nil : result.key)
    } label: {
      HStack(spacing: 8) {
        Text(result.label)
          .font(.body.weight(.medium))
          .frame(minWidth: 44, alignment: .leading)
        if let name = result.name, name != result.label {
          Text(name)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        Spacer(minLength: 0)
      }
      .lineLimit(1)
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .id(result.key)
    .accessibilityLabel(result.accessibilityLabel)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("\(identifierPrefix).result.\(result.key)")
  }
}

/// Toggles for the eight modifiers: a Left and a Right row in Mac order.
struct ModifierToggles: View {
  @Binding var modifiers: Modifiers
  /// False for media keys, which are sent without modifiers.
  var isEnabled = true
  /// Prefixes the toggles' accessibility identifiers (`<prefix>.modifier.<name>`).
  let identifierPrefix: String

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
      GridRow {
        Text("Left")
          .foregroundStyle(.secondary)
        ForEach(Self.left, id: \.self, content: toggle)
      }
      GridRow {
        Text("Right")
          .foregroundStyle(.secondary)
        ForEach(Self.right, id: \.self, content: toggle)
      }
    }
    .font(.callout)
  }

  private func toggle(_ modifier: Modifier) -> some View {
    Toggle(isOn: Binding(
      get: { modifiers.contains(Modifiers(modifier)) },
      set: { isOn in
        var updated = modifiers
        if isOn {
          updated.insert(Modifiers(modifier))
        } else {
          updated.remove(Modifiers(modifier))
        }
        modifiers = updated
      }
    )) {
      Text("\(Self.symbol(modifier)) \(Self.shortName(modifier))")
        .frame(minWidth: 52)
    }
    .toggleStyle(.button)
    .disabled(!isEnabled)
    .help(isEnabled ? Self.name(modifier) : "Media keys are sent without modifiers")
    .accessibilityLabel(Self.name(modifier))
    .accessibilityIdentifier("\(identifierPrefix).modifier.\(modifier.rawValue)")
  }

  /// Mac order: Control, Option, Shift, Command.
  private static let left: [Modifier] = [.leftControl, .leftOption, .leftShift, .leftCommand]
  private static let right: [Modifier] = [.rightControl, .rightOption, .rightShift, .rightCommand]

  static func symbol(_ modifier: Modifier) -> String {
    switch modifier {
    case .leftControl, .rightControl: "⌃"
    case .leftOption, .rightOption: "⌥"
    case .leftShift, .rightShift: "⇧"
    case .leftCommand, .rightCommand: "⌘"
    }
  }

  private static func shortName(_ modifier: Modifier) -> String {
    switch modifier {
    case .leftControl, .rightControl: "ctrl"
    case .leftOption, .rightOption: "opt"
    case .leftShift, .rightShift: "shift"
    case .leftCommand, .rightCommand: "cmd"
    }
  }

  static func name(_ modifier: Modifier) -> String {
    KeyNames.name(for: modifier.keyID) ?? modifier.rawValue
  }
}

/// The key recorder's button: bordered, or prominent red while recording.
struct RecordButtonStyle: PrimitiveButtonStyle {
  let isRecording: Bool

  func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
    if isRecording {
      Button(configuration).buttonStyle(.borderedProminent).tint(.red)
    } else {
      Button(configuration).buttonStyle(.bordered)
    }
  }
}
