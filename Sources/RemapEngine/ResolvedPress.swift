import Foundation
import KeymapModel

/// How a physical key's press was resolved. Stored at key-down so repeat and
/// key-up always follow the same resolution, whatever the layer or
/// configuration does in between.
enum ResolvedPress: Equatable, Sendable {
  /// No mapping. Re-evaluated per event: passes through unless synthetic
  /// modifiers are held, in which case the key is re-emitted with them.
  case unmapped
  /// Emits `key` with the effective modifiers plus `extra`.
  case emit(key: KeyID, extra: Modifiers)
  /// Holds `modifiers` synthetically while the key is down.
  case holdModifiers(Modifiers)
  /// Suppressed, no output.
  case block
  /// A keypress with a secondary role, held back. Its primary keypress and
  /// role live in `SecondaryRoleState`; activation replaces this resolution
  /// with `.block` (layer role) or `.holdModifiers` (modifier role).
  case pendingSecondaryRole
}
