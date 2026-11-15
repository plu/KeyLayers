public enum PeerRequirement {
  /// The requirement that admits only the helper: its bundle identifier, signed by `teamID`.
  public static func helper(bundleID: String, teamID: String) -> String {
    #"identifier "\#(bundleID)" and anchor apple generic"#
      + #" and certificate leaf[subject.OU] = "\#(teamID)""#
  }
}
