import Foundation
import KeymapModel

/// Keys whose secondary role is pending (Simple strategy): pressed, with the
/// primary keypress held back until the key is released (tap) or another key
/// goes down (the role activates). Ordered oldest first.
struct SecondaryRoleState: Equatable, Sendable {
  struct Pending: Equatable, Sendable {
    var key: KeyID
    var primary: Keypress
    var role: SecondaryRole
  }

  private(set) var pending: [Pending] = []

  mutating func add(_ key: KeyID, primary: Keypress, role: SecondaryRole) {
    _ = remove(key)
    pending.append(Pending(key: key, primary: primary, role: role))
  }

  /// Removes and returns `key`'s pending entry, if any.
  mutating func remove(_ key: KeyID) -> Pending? {
    guard let index = pending.firstIndex(where: { $0.key == key }) else { return nil }
    return pending.remove(at: index)
  }

  /// Removes and returns every pending entry, oldest first.
  mutating func removeAll() -> [Pending] {
    defer { pending = [] }
    return pending
  }
}
