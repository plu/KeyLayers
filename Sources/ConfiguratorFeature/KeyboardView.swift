import ComposableArchitecture
import KeyboardLayout
import KeymapModel
import SwiftUI

/// The drawing of a keyboard, each cap showing its action on `layer`; scales to the width (and
/// height) it's given.
struct KeyboardView: View {
  let geometry: KeyboardGeometry
  let keymap: Keymap
  let layer: LayerName
  /// For Switch Keymap actions' abbreviations.
  let keymaps: IdentifiedArrayOf<Keymap>
  let labels: [KeyID: String]
  /// The key action popover, shown on the cap of the key it edits.
  var keyAction: Binding<StoreOf<KeyActionEditorFeature>?> = .constant(nil)
  let keyTapped: (KeyID) -> Void

  /// The space between neighbouring caps, in key units.
  private static let gap: CGFloat = 0.1

  var body: some View {
    Color.clear
      .aspectRatio(geometry.size.width / geometry.size.height, contentMode: .fit)
      .overlay {
        GeometryReader { proxy in
          let unit = proxy.size.width / geometry.size.width
          ZStack(alignment: .topLeading) {
            ForEach(geometry.keys.indices, id: \.self) { index in
              cap(geometry.keys[index], unit: unit)
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("editor.keyboard")
  }

  @ViewBuilder
  private func cap(_ key: PhysicalKey, unit: CGFloat) -> some View {
    let gap = Self.gap * unit
    let frame = CGRect(
      x: key.frame.minX * unit + gap / 2,
      y: key.frame.minY * unit + gap / 2,
      width: key.frame.width * unit - gap,
      height: key.frame.height * unit - gap
    )
    let shape = KeyCapShape(
      cornerRadius: unit * 0.12,
      isoEnter: key.shape == .isoEnter ? (unit - gap, PhysicalKey.isoEnterNotch * unit) : nil
    )
    Group {
      if let id = key.keyID {
        let content = KeyCapContent.make(key: id, layer: layer, keymap: keymap, keymaps: keymaps, labels: labels)
        Button {
          keyTapped(id)
        } label: {
          KeyCapView(content: content, shape: shape, unit: unit)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KeyCapContent.spokenLabel(for: id, labels: labels))
        .accessibilityValue(content.accessibilityValue)
        .accessibilityIdentifier("key.\(id)")
        .popover(item: popover(for: id), arrowEdge: .bottom) { store in
          KeyActionEditorView(store: store)
        }
      } else {
        TouchIDCap(shape: shape)
      }
    }
    .frame(width: frame.width, height: frame.height)
    .offset(x: frame.minX, y: frame.minY)
  }
}

extension KeyboardView {
  /// The popover's store while it edits `key`.
  private func popover(for key: KeyID) -> Binding<StoreOf<KeyActionEditorFeature>?> {
    Binding(
      get: { keyAction.wrappedValue.flatMap { $0.key == key ? $0 : nil } },
      set: { store in
        // Only while it still edits `key`: another key may have taken the popover over.
        if store == nil, keyAction.wrappedValue?.key == key {
          keyAction.wrappedValue = nil
        }
      }
    )
  }
}

/// The Touch ID button: no key code, drawn for orientation only.
private struct TouchIDCap: View {
  let shape: KeyCapShape

  var body: some View {
    ZStack {
      shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
      shape.stroke(Color(nsColor: .separatorColor))
      Circle()
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1.5)
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(0.6)
    }
    .accessibilityHidden(true)
  }
}
