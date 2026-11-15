import ComposableArchitecture
import SwiftUI

/// Settings sheet: double-tap timeout, layer HUD, menu bar text, launch helper at login.
public struct SettingsView: View {
  let store: StoreOf<SettingsFeature>

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          Stepper(
            value: Binding(
              get: { store.configuration.settings.doubleTapTimeoutMilliseconds },
              set: { store.send(.doubleTapTimeoutChanged($0)) }
            ),
            in: SettingsFeature.doubleTapTimeoutRange,
            step: SettingsFeature.doubleTapTimeoutStep
          ) {
            HStack {
              Text("Double-tap timeout")
              Spacer()
              Text("\(store.configuration.settings.doubleTapTimeoutMilliseconds) ms")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("settings.doubleTap")
          .disabled(store.isReadOnly)

          Toggle(
            "Show the layer when it's toggled or locked",
            isOn: Binding(
              get: { store.configuration.settings.showLayerHUD },
              set: { store.send(.showLayerHUDChanged($0)) }
            )
          )
          .accessibilityIdentifier("settings.hud")
          .disabled(store.isReadOnly)
        } header: {
          Text("Remapping")
        } footer: {
          if store.isReadOnly {
            Text("These settings can't be changed while the configuration file can't be read.")
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Toggle(
            "Show keymap",
            isOn: Binding(
              get: { store.configuration.settings.menuBarShowsKeymap },
              set: { store.send(.menuBarShowsKeymapChanged($0)) }
            )
          )
          .accessibilityIdentifier("settings.menuBarKeymap")
          .disabled(store.isReadOnly)

          Toggle(
            "Show layer",
            isOn: Binding(
              get: { store.configuration.settings.menuBarShowsLayer },
              set: { store.send(.menuBarShowsLayerChanged($0)) }
            )
          )
          .accessibilityIdentifier("settings.menuBarLayer")
          .disabled(store.isReadOnly)
        } header: {
          Text("Menu Bar")
        }

        Section {
          Toggle(
            "Launch the helper at login",
            isOn: Binding(
              get: { store.launchAtLogin },
              set: { store.send(.launchAtLoginChanged($0)) }
            )
          )
          .accessibilityIdentifier("settings.launchAtLogin")
          if let registrationError = store.registrationError {
            Label(registrationError, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
        } header: {
          Text("Helper")
        }
      }
      .formStyle(.grouped)
      // One background for the whole sheet, so the button row doesn't sit on a separate band.
      .scrollContentBackground(.hidden)

      HStack {
        Spacer()
        Button("Done") { store.send(.doneTapped) }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("settings.done")
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 16)
    }
    .frame(width: 460, height: 430)
  }
}
