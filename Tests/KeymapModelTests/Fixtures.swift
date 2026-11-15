import Foundation

// swiftlint:disable line_length
enum Fixtures {
  static let v1 = """
  {
    "defaultKeymapID" : "00000000-0000-0000-0000-000000000001",
    "formatVersion" : 1,
    "keymaps" : [ {
      "abbreviation" : "DEF",
      "id" : "00000000-0000-0000-0000-000000000001",
      "layers" : {
        "base" : { "7:57" : { "layer" : "fn", "mode" : "holdAndDoubleTapToggle", "type" : "switchLayer" } },
        "fn" : {
          "7:4" : { "key" : "7:5", "modifiers" : [ "leftCommand" ], "secondaryRole" : { "modifier" : "leftShift", "type" : "modifier" }, "type" : "keypress" },
          "7:5" : { "type" : "block" },
          "7:6" : { "macroID" : "x", "type" : "playMacro" }
        }
      },
      "name" : "Default"
    } ],
    "settings" : { "doubleTapTimeoutMilliseconds" : 250, "showLayerHUD" : true }
  }
  """

  static let v2 = v1.replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 2")
}

// swiftlint:enable line_length
