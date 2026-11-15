import Foundation
import KeymapModel

public struct RemapEngine: Sendable {
  public private(set) var status: EngineStatus

  private var configuration: Configuration
  /// Resolution of every physically held key, keyed by physical key.
  private var presses: [KeyID: ResolvedPress] = [:]
  /// Physically held modifier keys that are not remapped.
  private var physicalModifiers: Modifiers = []
  /// Physically held modifier keys, whatever they are mapped to (emergency combo).
  private var rawModifiers: Modifiers = []
  private var roles = SecondaryRoleState()
  private var layers = LayerState()
  /// The last press of a double-tap-capable layer key, for lock detection.
  private var doubleTapCandidate: DoubleTapCandidate?

  private struct DoubleTapCandidate {
    var key: KeyID
    var pressedAt: UInt64
    /// Released with no other key pressed since.
    var released = false
  }

  public init(configuration: Configuration) {
    self.configuration = configuration
    status = EngineStatus(activeKeymapID: configuration.defaultKeymap.id, activeLayer: .base)
  }

  /// Keeps the active keymap if it still exists, otherwise falls back to the
  /// default keymap and resets layers. Stored press resolutions are kept.
  public mutating func update(configuration: Configuration) {
    self.configuration = configuration
    if configuration.keymaps[id: status.activeKeymapID] == nil {
      status.activeKeymapID = configuration.defaultKeymap.id
      resetLayers()
    }
    status.activeLayer = layers.active
  }

  /// Switches to keymap `id` and resets layers. Unknown IDs are ignored.
  public mutating func selectKeymap(_ id: Keymap.ID) -> EngineResult {
    guard configuration.keymaps[id: id] != nil else { return EngineResult(disposition: .passThrough) }
    return EngineResult(disposition: .suppress, notifications: switchKeymap(to: id))
  }

  /// Ups for every synthetic key and modifier currently down; clears held
  /// and latched layers, pending secondary roles, stored press resolutions and
  /// physical key tracking. Keeps the active keymap. Physically held,
  /// unremapped modifiers are left alone.
  public mutating func releaseAll() -> [OutputEvent] {
    let effective = effectiveModifiers
    let held = presses.sorted { ($0.key.page, $0.key.usage) < ($1.key.page, $1.key.usage) }
    var result: [OutputEvent] = held.compactMap { key, press in
      switch press {
      case let .emit(target, extra): output(target, .up, effective.union(extra))
      case .unmapped where key.modifier == nil: output(key, .up, effective)
      case .unmapped, .holdModifiers, .block, .pendingSecondaryRole: nil
      }
    }
    result += syntheticModifiers.subtracting(physicalModifiers).members
      .map { output($0.keyID, .up, physicalModifiers) }
    presses = [:]
    roles = SecondaryRoleState()
    resetLayers()
    physicalModifiers = []
    rawModifiers = []
    status.activeLayer = .base
    return result
  }

  public mutating func handle(_ event: KeyEvent) -> EngineResult {
    trackRawModifier(event)
    if event.phase == .down, event.key == .escape, rawModifiers.isSuperset(of: Self.emergencyModifiers) {
      return emergencyStop()
    }
    let resolution: ResolvedPress
    var activation: [OutputEvent] = []
    var notifications: [EngineNotification] = []
    // Synthetic modifiers held by other presses (before a down, after an up).
    let heldByOthers: Modifiers
    switch event.phase {
    case .down:
      if event.key != doubleTapCandidate?.key {
        doubleTapCandidate = nil
      }
      activation = activatePendingRoles(except: event.key)
      heldByOthers = syntheticModifiers
      (resolution, notifications) = resolve(event)
      presses[event.key] = resolution
    case .repeat:
      resolution = presses[event.key] ?? .unmapped
      heldByOthers = syntheticModifiers
    case .up:
      resolution = presses.removeValue(forKey: event.key) ?? .unmapped
      layers.release(source: event.key)
      if doubleTapCandidate?.key == event.key {
        doubleTapCandidate?.released = true
      }
      heldByOthers = syntheticModifiers
    }
    status.activeLayer = layers.active
    var result = apply(resolution, to: event, heldByOthers: heldByOthers)
    result.output.insert(contentsOf: activation, at: 0)
    result.notifications.insert(contentsOf: notifications, at: 0)
    return result
  }

  // MARK: - Emergency combo

  private static let emergencyModifiers: Modifiers = [
    Modifiers(.leftControl), Modifiers(.leftOption), Modifiers(.leftCommand),
  ]

  /// Tracks physical modifier keys from raw events, whatever they are mapped to.
  private mutating func trackRawModifier(_ event: KeyEvent) {
    guard let modifier = event.key.modifier else { return }
    switch event.phase {
    case .down: rawModifiers.insert(Modifiers(modifier))
    case .up: rawModifiers.remove(Modifiers(modifier))
    case .repeat: break
    }
  }

  private mutating func emergencyStop() -> EngineResult {
    let output = releaseAll()
    // Escape's own repeats and release stay suppressed.
    presses[.escape] = .block
    return EngineResult(disposition: .suppress, output: output, notifications: [.emergencyStop])
  }

  // MARK: - Secondary roles

  /// Activates every pending secondary role except `key`'s, oldest first.
  /// Returns the modifier downs of activated modifier roles.
  private mutating func activatePendingRoles(except key: KeyID) -> [OutputEvent] {
    var result: [OutputEvent] = []
    for pending in roles.pending where pending.key != key {
      _ = roles.remove(pending.key)
      switch pending.role {
      case let .layer(layer):
        // As with `.switchLayer`, the base layer is always active.
        if layer != .base {
          layers.hold(layer, source: pending.key)
        }
        presses[pending.key] = .block
      case let .modifier(modifier):
        let heldByOthers = syntheticModifiers
        presses[pending.key] = .holdModifiers(Modifiers(modifier))
        result += applyHeldModifiers(Modifiers(modifier), phase: .down, heldByOthers: heldByOthers)
      }
    }
    return result
  }

  /// A pending key released with no activation: its primary keypress, down then up.
  private mutating func tapPrimary(of event: KeyEvent, heldByOthers: Modifiers) -> EngineResult {
    guard let pending = roles.remove(event.key) else { return suppressed([]) }
    let primary = resolve(pending.primary)
    presses[event.key] = primary
    var downEvent = event
    downEvent.phase = .down
    let pressed = apply(primary, to: downEvent, heldByOthers: heldByOthers)
    presses[event.key] = nil
    let released = apply(primary, to: event, heldByOthers: heldByOthers)
    return suppressed(pressed.output + released.output)
  }

  // MARK: - Modifier state

  /// Modifiers held synthetically: by modifier-only keypresses and active
  /// modifier secondary roles.
  private var syntheticModifiers: Modifiers {
    presses.values.reduce(into: Modifiers()) { result, press in
      if case let .holdModifiers(modifiers) = press {
        result.formUnion(modifiers)
      }
    }
  }

  private var effectiveModifiers: Modifiers {
    physicalModifiers.union(syntheticModifiers)
  }

  // MARK: - Resolution

  private mutating func resolve(_ event: KeyEvent) -> (ResolvedPress, [EngineNotification]) {
    let key = event.key
    let keymap = configuration.keymaps[id: status.activeKeymapID] ?? configuration.defaultKeymap
    let action = keymap.action(for: key, on: layers.active)
      ?? keymap.action(for: key, on: .base)
    guard let action else { return (.unmapped, []) }
    switch action {
    case let .keypress(keypress):
      if let role = keypress.secondaryRole {
        roles.add(key, primary: keypress, role: role)
        return (.pendingSecondaryRole, [])
      }
      return (resolve(keypress), [])
    case .block, .unsupported:
      return (.block, [])
    case let .switchLayer(layer, mode):
      return (.block, applyLayerSwitch(layer, mode: mode, event: event))
    case let .switchKeymap(id):
      guard configuration.keymaps[id: id] != nil else { return (.block, []) }
      return (.block, switchKeymap(to: id))
    }
  }

  /// The keypress itself, ignoring any secondary role.
  private func resolve(_ keypress: Keypress) -> ResolvedPress {
    if let target = keypress.key, target.modifier == nil {
      return .emit(key: target, extra: keypress.modifiers)
    }
    var held = keypress.modifiers
    if let modifier = keypress.key?.modifier {
      held.insert(Modifiers(modifier))
    }
    return .holdModifiers(held)
  }

  private mutating func applyLayerSwitch(
    _ layer: LayerName,
    mode: LayerSwitchMode,
    event: KeyEvent
  ) -> [EngineNotification] {
    // The base layer is always active; switching to it is meaningless.
    guard layer != .base else { return [] }
    switch mode {
    case .hold:
      layers.hold(layer, source: event.key)
      return []
    case .toggle:
      return layers.latched == layer ? layers.unlatch() : layers.latch(layer)
    case .holdAndDoubleTapToggle:
      if layers.latched == layer {
        doubleTapCandidate = nil
        return layers.unlatch()
      }
      let milliseconds = min(max(0, configuration.settings.doubleTapTimeoutMilliseconds), Self.maxDoubleTapTimeout)
      let timeout = UInt64(milliseconds) * 1_000_000
      if completesDoubleTap(event, timeout: timeout) {
        doubleTapCandidate = nil
        return layers.latch(layer)
      }
      layers.hold(layer, source: event.key)
      doubleTapCandidate = DoubleTapCandidate(key: event.key, pressedAt: event.timestamp)
      return []
    }
  }

  /// Clamp for hand-edited timeouts, so the conversion to nanoseconds never overflows.
  private static let maxDoubleTapTimeout = 10000

  private func completesDoubleTap(_ event: KeyEvent, timeout: UInt64) -> Bool {
    guard let candidate = doubleTapCandidate, candidate.key == event.key, candidate.released,
          event.timestamp >= candidate.pressedAt
    else { return false }
    return event.timestamp - candidate.pressedAt <= timeout
  }

  private mutating func switchKeymap(to id: Keymap.ID) -> [EngineNotification] {
    status.activeKeymapID = id
    resetLayers()
    status.activeLayer = .base
    return [.keymapSwitched(id)]
  }

  private mutating func resetLayers() {
    layers.reset()
    doubleTapCandidate = nil
  }

  // MARK: - Application

  private mutating func apply(
    _ resolution: ResolvedPress,
    to event: KeyEvent,
    heldByOthers: Modifiers
  ) -> EngineResult {
    switch resolution {
    case .unmapped:
      applyPhysicalModifier(event)
      // The system already has this modifier down from a synthetic holder:
      // a physical down is redundant and a physical up would release it early.
      if let modifier = event.key.modifier, syntheticModifiers.contains(Modifiers(modifier)) {
        return suppressed([])
      }
      guard !syntheticModifiers.isEmpty else { return EngineResult(disposition: .passThrough) }
      return suppressed([output(event.key, event.phase, effectiveModifiers)])
    case let .emit(key, extra):
      return suppressed([output(key, event.phase, effectiveModifiers.union(extra))])
    case let .holdModifiers(modifiers):
      return suppressed(applyHeldModifiers(modifiers, phase: event.phase, heldByOthers: heldByOthers))
    case .block:
      return suppressed([])
    case .pendingSecondaryRole:
      guard event.phase == .up else { return suppressed([]) }
      return tapPrimary(of: event, heldByOthers: heldByOthers)
    }
  }

  private mutating func applyPhysicalModifier(_ event: KeyEvent) {
    guard let modifier = event.key.modifier else { return }
    switch event.phase {
    case .down: physicalModifiers.insert(Modifiers(modifier))
    case .up: physicalModifiers.remove(Modifiers(modifier))
    case .repeat: break
    }
  }

  /// Downs and ups only for modifiers that nothing else already holds down:
  /// neither a physical modifier nor another synthetic press. This keeps
  /// synthetic modifiers from clobbering physically held ones. Repeats are ignored.
  private func applyHeldModifiers(
    _ modifiers: Modifiers,
    phase: KeyEvent.Phase,
    heldByOthers: Modifiers
  ) -> [OutputEvent] {
    guard phase != .repeat else { return [] }
    let effective = effectiveModifiers
    return modifiers.subtracting(heldByOthers).subtracting(physicalModifiers).members
      .map { output($0.keyID, phase, effective) }
  }

  private func output(_ key: KeyID, _ phase: KeyEvent.Phase, _ modifiers: Modifiers) -> OutputEvent {
    OutputEvent(key: key, isDown: phase != .up, isRepeat: phase == .repeat, modifiers: modifiers)
  }

  private func suppressed(_ output: [OutputEvent]) -> EngineResult {
    EngineResult(disposition: .suppress, output: output)
  }
}
