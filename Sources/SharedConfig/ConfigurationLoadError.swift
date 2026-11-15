import Foundation
import KeymapModel

/// User-facing descriptions of why the configuration file couldn't be loaded.
public enum ConfigurationLoadError {
  /// `nil` when there is no error.
  public static func message(for error: (any Error)?) -> String? {
    switch error {
    case nil:
      nil
    case let ConfigurationError.newerFormat(version)?:
      "The configuration file was written by a newer version of KeyLayers (format version \(version))."
    case .some(is DecodingError):
      "The configuration file is damaged and can't be read."
    case let error?:
      "The configuration file couldn't be read: \(error.localizedDescription)"
    }
  }
}
