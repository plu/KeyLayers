import Carbon
import Dependencies
import DependenciesMacros
import Foundation
import KeyIO
import KeymapModel

/// Key cap labels from the current input source.
@DependencyClient
public struct KeyLabelClient: Sendable {
  public var labels: @Sendable () -> [KeyID: String] = { [:] }
  /// Yields whenever the selected input source changes.
  public var changes: @Sendable () -> AsyncStream<Void> = { .finished }
}

extension KeyLabelClient: DependencyKey {
  public static let liveValue = KeyLabelClient(
    labels: { LiveKeyLabels.current() },
    changes: { LiveKeyLabels.changes() }
  )

  public static let testValue = KeyLabelClient()

  public static let previewValue = KeyLabelClient(labels: { StaticKeyLabels.usANSI }, changes: { .finished })
}

public extension DependencyValues {
  var keyLabels: KeyLabelClient {
    get { self[KeyLabelClient.self] }
    set { self[KeyLabelClient.self] = newValue }
  }
}

/// `UCKeyTranslate` over the current keyboard layout for printing keys, `StaticKeyLabels` for the rest.
enum LiveKeyLabels {
  static func current() -> [KeyID: String] {
    guard let layoutData = KeyboardLayoutData.current()?.data else { return StaticKeyLabels.usANSI }
    var labels: [KeyID: String] = [:]
    layoutData.withUnsafeBytes { raw in
      guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
      for key in KeyID.allKnown {
        if let symbol = StaticKeyLabels.label(for: key) {
          labels[key] = symbol
        } else if let code = MacKeyCode.code(for: key), let text = translate(code, layout) {
          labels[key] = text
        }
      }
    }
    return labels
  }

  static func changes() -> AsyncStream<Void> {
    AsyncStream { continuation in
      let center = DistributedNotificationCenter.default()
      let token = center.addObserver(
        forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
        object: nil,
        queue: nil
      ) { _ in continuation.yield() }
      let observer = Observer(token: token)
      continuation.onTermination = { _ in center.removeObserver(observer.token) }
    }
  }

  private final class Observer: @unchecked Sendable {
    let token: any NSObjectProtocol
    init(token: any NSObjectProtocol) {
      self.token = token
    }
  }

  private static func translate(_ code: UInt16, _ layout: UnsafePointer<UCKeyboardLayout>) -> String? {
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = UCKeyTranslate(
      layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
    )
    guard status == noErr, length > 0 else { return nil }
    let text = String(utf16CodeUnits: characters, count: length)
    guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    let upper = text.uppercased()
    return upper.count == text.count ? upper : text
  }
}
