import Foundation

public extension Keymap {
  /// `base` if it's free, otherwise the first free of: its first two characters plus a digit 2…9
  /// ("NEW" → "NE2"), its first character plus 10…99 ("N10"), any three letters or digits.
  /// Never longer than three characters.
  static func uniqueAbbreviation(_ base: String, existing: Set<String>) -> String {
    guard existing.contains(base) else { return base }
    for digit in 2 ... 9 where !existing.contains("\(base.prefix(2))\(digit)") {
      return "\(base.prefix(2))\(digit)"
    }
    for number in 10 ... 99 where !existing.contains("\(base.prefix(1))\(number)") {
      return "\(base.prefix(1))\(number)"
    }
    let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    for a in characters {
      for b in characters {
        for c in characters where !existing.contains(String([a, b, c])) {
          return String([a, b, c])
        }
      }
    }
    return base
  }
}

public extension Configuration {
  /// This configuration with `other`'s keymaps appended; settings and default keymap stay.
  ///
  /// Every imported keymap gets a new ID from `newID`, drawn again while it is already in use, so
  /// nothing collides. Abbreviations are normalized and made unique ("DEF" → "DE2"), clashing names
  /// get " (imported)". `switchKeymap` actions that point at a keymap of `other` follow it to its
  /// new ID. Macros that imported keymaps use come along with new IDs (clashing names get
  /// " (imported)") and those actions follow them; unused macros stay behind. Any other target is
  /// kept as is: one that dangles in `other` but happens to be the ID of a keymap in this
  /// configuration therefore links to that keymap.
  func addingKeymaps(from other: Configuration, newID: () -> Keymap.ID = { UUID() }) -> Configuration {
    importingKeymaps(from: other, newID: newID).configuration
  }

  /// `addingKeymaps(from:newID:)`, plus the new ID of each of `other`'s keymaps (keyed by its old ID).
  func importingKeymaps(
    from other: Configuration,
    newID: () -> Keymap.ID = { UUID() }
  ) -> (configuration: Configuration, newIDs: [Keymap.ID: Keymap.ID]) {
    var used = Set(keymaps.ids).union(macros.ids)
    func freshID() -> UUID {
      var id = newID()
      var attempts = 1
      while used.contains(id) {
        // A generator that keeps repeating itself must not hang the import.
        id = attempts < 100 ? newID() : UUID()
        attempts += 1
      }
      used.insert(id)
      return id
    }
    var idMap: [Keymap.ID: Keymap.ID] = [:]
    for keymap in other.keymaps {
      idMap[keymap.id] = freshID()
    }
    let (importedMacros, macroIDMap) = macrosToImport(from: other, freshID: freshID)
    var result = self
    result.macros.append(contentsOf: importedMacros)
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
          switch action {
          case let .switchKeymap(target):
            idMap[target].map { .switchKeymap($0) } ?? action
          case let .macro(target):
            macroIDMap[target].map { .macro($0) } ?? action
          default:
            action
          }
        })
      }
      abbreviations.insert(keymap.abbreviation)
      names.insert(keymap.name)
      result.keymaps.append(keymap)
    }
    return (result, idMap)
  }

  /// The macros of `other` that its keymaps use, with new IDs and names unique among this
  /// configuration's, plus the old-to-new ID map.
  private func macrosToImport(
    from other: Configuration,
    freshID: () -> UUID
  ) -> (macros: [Macro], idMap: [Macro.ID: Macro.ID]) {
    let referenced = other.referencedMacroIDs
    var idMap: [Macro.ID: Macro.ID] = [:]
    var names = Set(macros.map(\.name))
    var imported: [Macro] = []
    for original in other.macros where referenced.contains(original.id) {
      var macro = original
      macro.id = freshID()
      macro.name = Self.uniqueName(original.name, existing: names)
      names.insert(macro.name)
      idMap[original.id] = macro.id
      imported.append(macro)
    }
    return (imported, idMap)
  }

  private var referencedMacroIDs: Set<Macro.ID> {
    Set(keymaps.flatMap { keymap in
      keymap.layers.values.flatMap { layer in
        layer.actions.values.compactMap { action -> Macro.ID? in
          if case let .macro(id) = action {
            id
          } else {
            nil
          }
        }
      }
    })
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
