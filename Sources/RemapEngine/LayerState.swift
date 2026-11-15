import Foundation
import KeymapModel

/// Which layers are active. A held layer is owned by a physical *source key*,
/// which can be any key (a `.switchLayer` key or a secondary-role key). At
/// most one layer is latched (toggle or double-tap lock).
struct LayerState: Equatable, Sendable {
  private struct Held: Equatable, Sendable {
    var source: KeyID
    var layer: LayerName
  }

  /// Oldest first; the last entry is the most recently pressed.
  private var held: [Held] = []
  private(set) var latched: LayerName?

  /// The most recently pressed held layer, else the latched layer, else `.base`.
  var active: LayerName {
    held.last?.layer ?? latched ?? .base
  }

  /// Activates `layer` until `source` is released.
  mutating func hold(_ layer: LayerName, source: KeyID) {
    release(source: source)
    held.append(Held(source: source, layer: layer))
  }

  /// Ends whatever layer `source` was holding. No-op if it held none.
  mutating func release(source: KeyID) {
    held.removeAll { $0.source == source }
  }

  /// Latches `layer`, replacing any other latched layer.
  /// Returns the notifications describing the change.
  mutating func latch(_ layer: LayerName) -> [EngineNotification] {
    guard latched != layer else { return [] }
    var notifications = unlatch()
    latched = layer
    notifications.append(.layerLatched(layer))
    return notifications
  }

  mutating func unlatch() -> [EngineNotification] {
    guard let layer = latched else { return [] }
    latched = nil
    return [.layerUnlatched(layer)]
  }

  mutating func reset() {
    held = []
    latched = nil
  }
}
