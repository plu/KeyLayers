import ComposableArchitecture
import HelperIPC
import SwiftUI

/// The status area: helper state, registration, permissions, configuration errors, pause.
public struct StatusView: View {
  let store: StoreOf<StatusFeature>

  public init(store: StoreOf<StatusFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: indicator.symbol)
          .foregroundStyle(indicator.color)
          .accessibilityHidden(true)
        Text(store.headline)
          .font(.headline)
          .accessibilityIdentifier("status.helper")
        Spacer(minLength: 8)
        if store.showsEnableHelper {
          Button(store.enableHelperTitle) { store.send(.enableHelperTapped) }
            .accessibilityIdentifier("status.enableHelper")
        }
        if store.showsStartHelper {
          Button("Start Helper") { store.send(.startHelperTapped) }
            .accessibilityIdentifier("status.startHelper")
        }
        if let status = store.runningStatus {
          // Never disabled while a request is in flight: a wedged helper may not reply.
          Button(status.isPaused ? "Resume Remapping" : "Pause Remapping") { store.send(.pauseToggled) }
            .accessibilityIdentifier("status.pause")
        }
      }

      if let status = store.runningStatus {
        PermissionRow(
          title: "Accessibility",
          isGranted: status.permissions.accessibility,
          identifier: "status.openAccessibility"
        ) { store.send(.openSettingsTapped(.accessibility)) }
        if let note = store.modifierKeysNote {
          Text(note)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("status.modifierKeysNote")
        }
        if store.showsInputServiceInputMonitoringStep {
          VStack(alignment: .leading, spacing: 6) {
            Label(
              "KeyLayers' input service needs Input Monitoring. Click + in Input Monitoring and add KeyLayersInputDaemon.",
              systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("status.inputServiceInputMonitoring")
            HStack(spacing: 8) {
              Button("Open Input Monitoring…") { store.send(.openSettingsTapped(.inputMonitoring)) }
                .accessibilityIdentifier("status.openInputMonitoring")
              Button("Show in Finder") { store.send(.showInputServiceInFinderTapped) }
                .accessibilityIdentifier("status.showInputServiceInFinder")
            }
            .controlSize(.small)
          }
          .padding(.leading, 4)
        }
        if let configError = status.configError {
          Label(configError, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("status.configError")
        }
      }

      if let registrationError = store.registrationMessage {
        Label(registrationError, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("status.registrationError")
      }

      Text("Emergency stop: ⌃⌥⌘⎋")
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("status.emergencyCombo")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var indicator: (symbol: String, color: Color) {
    guard let status = store.runningStatus else {
      return store.registration == .requiresApproval
        ? ("exclamationmark.circle.fill", .orange)
        : ("xmark.circle.fill", .red)
    }
    if store.daemonNeedsApproval || !status.permissions.allGranted || status.inputServiceNeedsInputMonitoring {
      return ("exclamationmark.circle.fill", .orange)
    }
    return status.isPaused ? ("pause.circle.fill", .orange) : ("checkmark.circle.fill", .green)
  }
}

private struct PermissionRow: View {
  let title: String
  let isGranted: Bool
  let identifier: String
  let open: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: isGranted ? "checkmark" : "xmark")
        .foregroundStyle(isGranted ? Color.green : Color.red)
        .frame(width: 14)
        .accessibilityHidden(true)
      Text("\(title): \(isGranted ? "allowed" : "not allowed")")
      if !isGranted {
        Button("Open System Settings…", action: open)
          .controlSize(.small)
          .accessibilityIdentifier(identifier)
      }
    }
    .padding(.leading, 4)
  }
}
