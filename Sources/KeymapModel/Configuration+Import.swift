import Foundation

public extension Keymap {
  /// `base`, or if that's taken its first two characters plus the first free digit 2…9
  /// ("NEW" → "NE2"); `base` again when all of those are taken too.
  static func uniqueAbbreviation(_ base: String, existing: Set<String>) -> String {
    guard existing.contains(base) else { return base }
    let prefix = base.prefix(2)
    return (2 ... 9).lazy.map { "\(prefix)\($0)" }.first { !existing.contains($0) } ?? base
  }
}

public extension Configuration {
  /// This configuration with `other`'s keymaps appended; settings and default keymap stay.
  ///
  /// Every imported keymap gets a new ID from `newID`, so nothing collides. Abbreviations are
  /// normalized and made unique ("DEF" → "DE2"), clashing names get " (imported)". `switchKeymap`
  /// actions that point at a keymap of `other` follow it to its new ID; any other target is kept.
  func addingKeymaps(from other: Configuration, newID: () -> Keymap.ID = { UUID() }) -> Configuration {
    var idMap: [Keymap.ID: Keymap.ID] = [:]
    for keymap in other.keymaps {
      idMap[keymap.id] = newID()
    }
    var result = self
    var abbreviations = Set(keymaps.map(\.abbreviation))
    var names = Set(keymaps.map(\.name))
    for original in other.keymaps {
      var keymap = original
      keymap.id = idMap[original.id]!
      keymap.abbreviation = Keymap.uniqueAbbreviation(
        Keymap.normalizedAbbreviation(original.abbreviation),
        existing: abbreviations
      )
      keymap.name = Self.uniqueName(original.name, existing: names)
      keymap.layers = original.layers.mapValues { layer in
        Layer(actions: layer.actions.mapValues { action in
          if case let .switchKeymap(target) = action, let renamed = idMap[target] {
            return .switchKeymap(renamed)
          }
          return action
        })
      }
      abbreviations.insert(keymap.abbreviation)
      names.insert(keymap.name)
      result.keymaps.append(keymap)
    }
    return result
  }

  /// `name`, else "name (imported)", else "name (imported 2)", "… 3", ….
  private static func uniqueName(_ name: String, existing: Set<String>) -> String {
    guard existing.contains(name) else { return name }
    let imported = "\(name) (imported)"
    guard existing.contains(imported) else { return imported }
    var n = 2
    while existing.contains("\(name) (imported \(n))") {
      n += 1
    }
    return "\(name) (imported \(n))"
  }
}
