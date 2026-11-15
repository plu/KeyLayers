import Foundation
import KeymapModel
import Sharing

extension SharedKey where Self == FileStorageKey<Configuration>.Default {
  /// The configuration file shared by the configurator and the helper.
  public static var configuration: Self {
    configuration(at: AppIdentifiers.configurationURL)
  }

  static func configuration(at url: URL) -> Self {
    Self[
      .fileStorage(
        url,
        decode: { try Configuration.decoder.decode(Configuration.self, from: $0) },
        encode: { try Configuration.encoder.encode($0) }
      ),
      default: .starter
    ]
  }
}
