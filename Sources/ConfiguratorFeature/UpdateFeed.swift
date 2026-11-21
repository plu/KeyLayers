import Foundation

/// Whether this build updates itself. Only the release workflow's tag builds carry Sparkle's feed URL
/// and public key; every other build (dev, a local release, a workflow_dispatch artifact, a fork)
/// has both empty and must not offer, or install, the latest public release over itself.
public enum UpdateFeed {
  public static func isConfigured(infoDictionary: [String: Any]?) -> Bool {
    let feed = infoDictionary?["SUFeedURL"] as? String ?? ""
    let key = infoDictionary?["SUPublicEDKey"] as? String ?? ""
    return !feed.isEmpty && !key.isEmpty
  }
}
