import Foundation

/// Identifies one version of a file on disk: replaced files get a new inode, rewritten ones a new
/// modification time or size. The daemon and the helper each compare their own executable's identity
/// at launch with the current one to notice that an update or build replaced it.
public struct ExecutableIdentity: Equatable, Sendable {
  public let device: Int64
  public let inode: UInt64
  public let modificationSeconds: Int64
  public let modificationNanoseconds: Int64
  public let size: Int64

  /// The identity of the file at `path` (symlinks followed); `nil` when it can't be stat'ed.
  public static func current(path: String) -> ExecutableIdentity? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return ExecutableIdentity(
      device: Int64(info.st_dev),
      inode: UInt64(info.st_ino),
      modificationSeconds: Int64(info.st_mtimespec.tv_sec),
      modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec),
      size: Int64(info.st_size)
    )
  }

  /// Whether the file at `path` is no longer the one identified by `launch`; a file that can't be
  /// stat'ed now (mid-replace) counts as changed. Without a path or a launch identity there is
  /// nothing to compare with, and nothing counts as changed (else every check would say "changed").
  public static func hasChanged(path: String?, since launch: ExecutableIdentity?) -> Bool {
    guard let path, let launch else { return false }
    return current(path: path) != launch
  }
}
