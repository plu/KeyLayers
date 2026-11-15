import AppKit
import Dependencies
import DependenciesMacros
import SwiftUI

/// Flashes a short message (layer or keymap name) over all other windows.
@DependencyClient
public struct HUDClient: Sendable {
  public var show: @Sendable (_ text: String) async -> Void
}

extension HUDClient: DependencyKey {
  public static let liveValue = HUDClient(
    show: { text in
      await MainActor.run { HUDPanelController.shared.show(text) }
    }
  )

  public static let testValue = HUDClient()
}

public extension DependencyValues {
  var hud: HUDClient {
    get { self[HUDClient.self] }
    set { self[HUDClient.self] = newValue }
  }
}

/// Owns the HUD panel: borderless, non-activating, click-through, at status-bar level. Each `show`
/// replaces the text, shows the panel at full opacity, and fades it out after `visibleDuration`.
@MainActor
final class HUDPanelController {
  static let shared = HUDPanelController()

  private let visibleDuration: Duration = .seconds(1)
  private let fadeDuration: TimeInterval = 0.3
  private var panel: NSPanel?
  /// Incremented per `show`, so an older show's fade doesn't hide a newer message.
  private var generation = 0

  func show(_ text: String) {
    generation += 1
    let generation = generation
    let panel = panel ?? makePanel()
    self.panel = panel

    let hostingView = NSHostingView(rootView: LayerHUDView(text: text))
    hostingView.frame.size = hostingView.fittingSize
    panel.contentView = hostingView
    panel.setContentSize(hostingView.fittingSize)
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      panel.setFrameOrigin(NSPoint(
        x: frame.midX - panel.frame.width / 2,
        y: frame.minY + frame.height * 0.2
      ))
    }
    panel.alphaValue = 1
    panel.orderFrontRegardless()

    let visibleDuration = visibleDuration
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: visibleDuration)
      self?.fadeOut(generation: generation)
    }
  }

  private func fadeOut(generation: Int) {
    guard generation == self.generation, let panel else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = fadeDuration
      panel.animator().alphaValue = 0
    } completionHandler: {
      MainActor.assumeIsolated {
        if generation == self.generation {
          self.panel?.orderOut(nil)
        }
      }
    }
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    return panel
  }
}
