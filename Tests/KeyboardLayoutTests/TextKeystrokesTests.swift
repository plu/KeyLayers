import Carbon
@testable import KeyboardLayout
import KeymapModel
import Testing

struct TextKeystrokesTests {
  private static func table(_ inputSourceID: String) throws -> TextKeystrokes {
    let data = try #require(KeyboardLayoutData.layoutData(inputSourceID: inputSourceID))
    return TextKeystrokes(layoutData: data, keyboardType: UInt32(LMGetKbdType()))
  }

  @Test func usLayout() throws {
    let us = try Self.table("com.apple.keylayout.US")
    #expect(us.strokes(for: "a") == [TextStroke(key: .a, modifiers: [])])
    #expect(us.strokes(for: "A") == [TextStroke(key: .a, modifiers: [Modifiers(.leftShift)])])
    #expect(us.strokes(for: "@") == [TextStroke(key: .digit2, modifiers: [Modifiers(.leftShift)])])
    let acuteE = [TextStroke(key: .e, modifiers: [Modifiers(.leftOption)]), TextStroke(key: .e, modifiers: [])]
    #expect(us.strokes(for: "é") == acuteE)
    #expect(us.strokes(for: "\n") == [TextStroke(key: .returnOrEnter, modifiers: [])])
    #expect(us.strokes(for: "\r\n") == [TextStroke(key: .returnOrEnter, modifiers: [])])
    #expect(us.strokes(for: "\r") == [TextStroke(key: .returnOrEnter, modifiers: [])])
    #expect(us.strokes(for: "\t") == [TextStroke(key: .tab, modifiers: [])])
    #expect(us.strokes(for: "☕") == nil)
  }

  @Test func germanLayout() throws {
    let german = try Self.table("com.apple.keylayout.German")
    #expect(german.strokes(for: "z") == [TextStroke(key: .y, modifiers: [])])
    #expect(german.strokes(for: "ö") == [TextStroke(key: .semicolon, modifiers: [])])
    #expect(german.strokes(for: "@") == [TextStroke(key: .l, modifiers: [Modifiers(.leftOption)])])
  }
}

/// Serialized: both tests start from no table.
@Suite(.serialized)
struct LiveTextKeystrokesTests {
  private static let characters: [Character] = ["a", "A", "1", "@", "é", "\n", "\t"]

  /// The current input source's table, built directly.
  @MainActor private static func expectedStrokes() throws -> [[TextStroke]?] {
    let current = try #require(KeyboardLayoutData.current())
    let table = TextKeystrokes(layoutData: current.data, keyboardType: UInt32(LMGetKbdType()))
    return characters.map { table.strokes(for: $0) }
  }

  /// On the main thread (the configurator's reducers) there is no waiting for a warm-up: the first
  /// call builds the table right there.
  @MainActor @Test func mainThreadCallBuildsTheTableAtOnce() throws {
    LiveTextKeystrokes.reset()
    #expect(try Self.characters.map { LiveTextKeystrokes.strokes(for: $0) } == (Self.expectedStrokes()))
  }

  /// `strokes` never waits for the main thread: with the main thread blocked and no table yet, a
  /// background call returns nil at once. Once the main thread is free, the build it scheduled there
  /// (`LiveTextKeystrokes` asserts the main thread) yields the current layout's table.
  @Test(.timeLimit(.minutes(1)))
  func backgroundCallsNeverBlockAndSeeTheTableOnceBuilt() async throws {
    LiveTextKeystrokes.reset()
    let whileMainIsBlocked = await Task.detached { Self.strokesWhileMainIsBlocked() }.value
    #expect(whileMainIsBlocked == nil)

    let expected = try await Self.expectedStrokes()
    var live: [[TextStroke]?] = []
    for _ in 0 ..< 200 {
      live = await Task.detached { Self.characters.map { LiveTextKeystrokes.strokes(for: $0) } }.value
      if live == expected {
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(live == expected)
  }

  /// Calls `strokes` while the main queue is stuck in a block; a `main.sync` inside would deadlock.
  private static func strokesWhileMainIsBlocked() -> [TextStroke]? {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
      entered.signal()
      release.wait()
    }
    entered.wait()
    defer { release.signal() }
    return LiveTextKeystrokes.strokes(for: "a")
  }
}
