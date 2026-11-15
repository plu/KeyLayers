import XCTest

/// End-to-end flows through the configurator, launched in UI-test mode (see `UITestMode`).
@MainActor
final class ConfiguratorUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    app?.terminate()
    app = nil
  }

  func testAssignKeypressWithSecondaryRole() {
    launch()
    click("keymap.row.DEF")
    click("layer.fn")
    openPopover(on: "7:4")
    click("popover.tab.keypress")
    let search = element("popover.keypress.search")
    search.click()
    search.typeText("b")
    click("popover.keypress.result.7:5")
    click("popover.keypress.modifier.leftCommand")
    chooseMenuItem("secondary.layer.mod", in: "popover.keypress.secondaryRole")
    apply()
    XCTAssertEqual(app.buttons["key.7:4"].value as? String, "⌘B Mod")
  }

  func testAssignLayerActionModes() {
    launch()
    let modes = [
      ("Hold: active while held", "Fn hold"),
      ("Toggle: tap to switch on and off", "Fn toggle"),
      ("Hold, or double-tap to lock", "Fn 2×lock"),
    ]
    for (mode, expected) in modes {
      openPopover(on: "7:43")
      click("popover.tab.layer")
      choosePopUpItem("Fn", in: "popover.layer.target")
      let radio = element("popover.layer.mode").radioButtons[mode]
      XCTAssertTrue(radio.waitForExistence(timeout: 5), "No mode \(mode)")
      radio.click()
      apply()
      XCTAssertEqual(app.buttons["key.7:43"].value as? String, expected)
    }
  }

  func testAssignKeymapAction() {
    launch()
    click("keymap.add")
    XCTAssertTrue(element("keymap.row.NEW").waitForExistence(timeout: 5))
    click("keymap.row.DEF")
    openPopover(on: "7:5")
    click("popover.tab.keymap")
    choosePopUpItem("New Keymap (NEW)", in: "popover.keymap.target")
    apply()
    XCTAssertEqual(app.buttons["key.7:5"].value as? String, "NEW keymap")
  }

  func testNoneBlockAndTransparent() {
    launch()
    openPopover(on: "7:4")
    click("popover.tab.none")
    setCheckbox("popover.none.block", on: true)
    apply()
    XCTAssertEqual(app.buttons["key.7:4"].value as? String, "✕")

    // On Fn: block, then make it transparent again; it shows its Base cap.
    click("layer.fn")
    openPopover(on: "7:5")
    click("popover.tab.none")
    setCheckbox("popover.none.block", on: true)
    apply()
    XCTAssertEqual(app.buttons["key.7:5"].value as? String, "✕")
    openPopover(on: "7:5")
    setCheckbox("popover.none.block", on: false)
    apply()
    XCTAssertEqual(app.buttons["key.7:5"].value as? String, "B")
    // An upper layer inherits Base's action, even a blocked one.
    XCTAssertEqual(app.buttons["key.7:4"].value as? String, "✕")
  }

  func testRecordKey() {
    launch(recordedKey: "7:14")
    openPopover(on: "7:4")
    click("popover.tab.keypress")
    click("popover.keypress.record")
    let selected = element("popover.keypress.selected")
    XCTAssertTrue(waitFor(selected, text: "K"), "Recorded key shows \(text(of: selected))")
    apply()
    XCTAssertEqual(app.buttons["key.7:4"].value as? String, "K")
  }

  func testRenameAndDeleteKeymap() {
    launch()
    click("keymap.row.DEF")
    replaceText(in: "editor.name", with: "Coding")
    replaceText(in: "editor.abbreviation", with: "cod\r")
    let renamed = element("keymap.row.COD")
    XCTAssertTrue(renamed.waitForExistence(timeout: 5))
    XCTAssertTrue(renamed.label.contains("Coding"), "Row label: \(renamed.label)")
    XCTAssertFalse(element("keymap.row.DEF").exists)

    click("keymap.add")
    let added = element("keymap.row.NEW")
    XCTAssertTrue(added.waitForExistence(timeout: 5))
    click("keymap.delete")
    let confirm = app.buttons["Delete"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No delete confirmation")
    confirm.click()
    XCTAssertTrue(waitForDisappearance(added), "Deleted keymap's row is still shown")
    XCTAssertTrue(renamed.exists)
  }

  func testStatusReflectsHelperState() {
    launch(helper: .notRunning)
    let status = element("status.helper")
    XCTAssertTrue(status.waitForExistence(timeout: 10))
    XCTAssertTrue(waitFor(status, containing: "not running"), "Status: \(text(of: status))")
    XCTAssertFalse(element("status.openAccessibility").exists)
    // Registered but not running (e.g. quit from its menu): offered a start.
    XCTAssertTrue(element("status.startHelper").exists)
    app.terminate()

    launch(helper: .needsPermissions)
    XCTAssertTrue(element("status.openAccessibility").waitForExistence(timeout: 10))
  }

  func testStarterKeymapShownOnFirstLaunch() {
    launch()
    XCTAssertEqual(app.buttons["key.7:57"].value as? String, "⎋ Mod")
  }

  // MARK: - Helpers

  private func launch(helper: FakeHelperState = .running, recordedKey: String? = nil) {
    app = XCUIApplication.launchConfigurator(helper: helper, recordedKey: recordedKey)
    XCTAssertTrue(app.buttons["key.7:4"].waitForExistence(timeout: 20), "The keyboard isn't shown")
  }

  /// The element with accessibility identifier `identifier`, whatever its type.
  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func click(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
    let target = element(identifier)
    XCTAssertTrue(target.waitForExistence(timeout: 5), "No element \(identifier)", file: file, line: line)
    target.click()
  }

  private func openPopover(on key: String, file: StaticString = #filePath, line: UInt = #line) {
    click("key.\(key)", file: file, line: line)
    XCTAssertTrue(element("popover.apply").waitForExistence(timeout: 5), "No popover", file: file, line: line)
  }

  private func apply(file: StaticString = #filePath, line: UInt = #line) {
    click("popover.apply", file: file, line: line)
    XCTAssertTrue(waitForDisappearance(element("popover.apply")), "Popover still open", file: file, line: line)
  }

  /// Opens the `Menu` `menu` and clicks its item `identifier` (SwiftUI passes a `Button`'s
  /// identifier on to its menu item).
  private func chooseMenuItem(_ identifier: String, in menu: String) {
    click(menu)
    let item = app.menuItems[identifier]
    XCTAssertTrue(item.waitForExistence(timeout: 5), "No menu item \(identifier)")
    item.click()
  }

  /// Opens the pop-up button `popUp` and clicks its item titled `title` (a `Picker`'s options
  /// carry no identifiers).
  private func choosePopUpItem(_ title: String, in popUp: String) {
    click(popUp)
    let item = element(popUp).menuItems[title]
    XCTAssertTrue(item.waitForExistence(timeout: 5), "No menu item \(title) in \(popUp)")
    item.click()
  }

  private func setCheckbox(_ identifier: String, on isOn: Bool) {
    let checkbox = element(identifier)
    XCTAssertTrue(checkbox.waitForExistence(timeout: 5), "No checkbox \(identifier)")
    if Self.isOn(checkbox) != isOn {
      checkbox.click()
    }
    XCTAssertEqual(Self.isOn(checkbox), isOn, "\(identifier) didn't change")
  }

  private static func isOn(_ checkbox: XCUIElement) -> Bool {
    switch checkbox.value {
    case let number as NSNumber: number.boolValue
    case let string as String: string == "1"
    default: false
    }
  }

  private func replaceText(in identifier: String, with text: String) {
    click(identifier)
    let field = element(identifier)
    field.typeKey("a", modifierFlags: .command)
    field.typeText(text)
  }

  /// A static text's string: its value, or its label when it has no value.
  private func text(of element: XCUIElement) -> String {
    if let value = element.value as? String, !value.isEmpty {
      return value
    }
    return element.label
  }

  private func waitFor(_ element: XCUIElement, text expected: String, timeout: TimeInterval = 5) -> Bool {
    waitUntil(timeout: timeout) { self.text(of: element) == expected }
  }

  private func waitFor(_ element: XCUIElement, containing expected: String, timeout: TimeInterval = 5) -> Bool {
    waitUntil(timeout: timeout) { self.text(of: element).contains(expected) }
  }

  private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    waitUntil(timeout: timeout) { !element.exists }
  }

  private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
  }
}
