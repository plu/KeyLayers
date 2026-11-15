@testable import KeyIO
import KeymapModel
import RemapEngine
import Testing

struct OutputRouterTests {
  private func down(_ key: KeyID) -> OutputEvent { OutputEvent(key: key, isDown: true, modifiers: []) }
  private func up(_ key: KeyID) -> OutputEvent { OutputEvent(key: key, isDown: false, modifiers: []) }

  @Test func downGoesToSource() {
    var router = OutputRouter()
    #expect(router.route(down(.a), source: 2, fallback: 9) == 2)
  }

  @Test func upFollowsItsDown() {
    var router = OutputRouter()
    _ = router.route(down(.a), source: 1, fallback: 9)
    #expect(router.route(up(.a), source: 2, fallback: 9) == 1)
  }

  @Test func noSourceUsesFallback() {
    var router = OutputRouter()
    #expect(router.route(down(.a), source: nil, fallback: 9) == 9)
    #expect(router.route(up(.b), source: nil, fallback: 9) == 9)
  }

  @Test func forgetReturnsHeldKeys() {
    var router = OutputRouter()
    _ = router.route(down(.a), source: 1, fallback: 9)
    _ = router.route(down(.b), source: 2, fallback: 9)
    #expect(router.forget(device: 1) == [.a])
    #expect(router.route(up(.b), source: 1, fallback: 9) == 2)
    #expect(router.forget(device: 1).isEmpty)
  }
}
