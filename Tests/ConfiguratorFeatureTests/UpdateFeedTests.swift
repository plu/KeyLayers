import ConfiguratorFeature
import Testing

struct UpdateFeedTests {
  private let feed = "https://github.com/plu/KeyLayers/releases/latest/download/appcast.xml"
  private let key = "zuh9sXp3zdrSHs7Hc+gxeRhfqkjCyOAhVjWHSyoLnAs="

  @Test func tagBuildWithFeedAndKeyUpdates() {
    #expect(UpdateFeed.isConfigured(infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": key]))
  }

  @Test func buildWithoutEitherValueNeverUpdates() {
    // Dev, local release and workflow_dispatch builds: both settings expand to "".
    #expect(!UpdateFeed.isConfigured(infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": ""]))
    #expect(!UpdateFeed.isConfigured(infoDictionary: [:]))
    #expect(!UpdateFeed.isConfigured(infoDictionary: nil))
  }

  @Test func feedWithoutKeyNeverUpdates() {
    #expect(!UpdateFeed.isConfigured(infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": ""]))
  }

  @Test func keyWithoutFeedNeverUpdates() {
    #expect(!UpdateFeed.isConfigured(infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": key]))
  }
}
