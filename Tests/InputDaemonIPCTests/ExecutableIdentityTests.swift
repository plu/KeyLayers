import Foundation
import InputDaemonIPC
import Testing

struct ExecutableIdentityTests {
  private func temporaryFile() throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("daemon").path
  }

  @Test func executableIdentityDetectsRewrite() throws {
    let path = try temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    try Data("one".utf8).write(to: URL(fileURLWithPath: path))
    let before = try #require(ExecutableIdentity.current(path: path))
    #expect(ExecutableIdentity.current(path: path) == before)

    // Replaced by a new file (what a build or an update does): new inode.
    try FileManager.default.removeItem(atPath: path)
    try Data("two, longer".utf8).write(to: URL(fileURLWithPath: path))
    let after = try #require(ExecutableIdentity.current(path: path))
    #expect(after != before)
  }

  @Test func rewriteInPlaceIsDetected() throws {
    let path = try temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    try Data("one".utf8).write(to: URL(fileURLWithPath: path))
    let before = try #require(ExecutableIdentity.current(path: path))
    try Data("longer contents".utf8).write(to: URL(fileURLWithPath: path))
    #expect(ExecutableIdentity.current(path: path) != before)
  }

  @Test func missingExecutableCountsAsChanged() throws {
    let path = try temporaryFile()
    #expect(ExecutableIdentity.current(path: path) == nil)
  }

  @Test func sameSizeRewriteWithOnlyANewModificationTimeIsDetected() throws {
    let path = try temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    try Data("one".utf8).write(to: URL(fileURLWithPath: path))
    let before = try #require(ExecutableIdentity.current(path: path))
    // Same inode, same size, same bytes: only the modification time moves.
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try handle.write(contentsOf: Data("one".utf8))
    try handle.close()
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: path)
    let after = try #require(ExecutableIdentity.current(path: path))
    #expect(after.inode == before.inode && after.size == before.size && after.device == before.device)
    #expect(after != before)
  }

  @Test func hasChangedComparesWithTheLaunchIdentity() throws {
    let path = try temporaryFile()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    try Data("one".utf8).write(to: URL(fileURLWithPath: path))
    let launch = ExecutableIdentity.current(path: path)
    #expect(!ExecutableIdentity.hasChanged(path: path, since: launch))
    try FileManager.default.removeItem(atPath: path)
    // Missing now (mid-replace): changed.
    #expect(ExecutableIdentity.hasChanged(path: path, since: launch))
  }

  @Test func withoutPathOrLaunchIdentityNothingCountsAsChanged() throws {
    let path = try temporaryFile()
    // No executable path: the check is off, or every connection would make the daemon exit.
    #expect(!ExecutableIdentity.hasChanged(path: nil, since: nil))
    #expect(!ExecutableIdentity.hasChanged(path: path, since: nil))
  }
}
