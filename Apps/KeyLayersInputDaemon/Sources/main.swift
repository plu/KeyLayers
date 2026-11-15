import Foundation
import InputDaemonCore
import InputDaemonIPC
import IOKit.hid
import OSLog
import SharedConfig

let logger = Logger(subsystem: "com.plunien.keylayers", category: "InputDaemon")

guard let teamID = AppIdentifiers.teamID else {
  logger.error("SigningTeamIdentifier missing from Info.plist; refusing to serve unauthenticated peers")
  exit(78) // EX_CONFIG
}

logger.notice("input daemon started, uid \(getuid())")

let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
logger.notice("input monitoring access: \(access.rawValue)")
if access != kIOHIDAccessTypeGranted {
  // Registers the daemon with TCC so it shows up in Input Monitoring; harmless otherwise.
  let requested = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
  logger.notice("input monitoring request returned \(requested)")
}

/// How long to wait for the client's last messages to leave the process before exiting.
let flushTimeout: Duration = .seconds(1)

// macOS caches the Input Monitoring decision per process. Exit so launchd relaunches the daemon on
// the helper's next connection, which gets a fresh check.
//
// The handler runs on the controller's delivery queue right after the not-permitted report was
// handed to the connection; `remoteObjectProxy` sends are asynchronous, so flush the connection
// before exiting or the helper may never learn why. Shutdown's own final `devicesChanged([])` is
// queued behind this handler and never sent (we exit first); that's fine: nothing is seized, and
// the helper sees the connection drop and reconnects.
nonisolated(unsafe) var controllerRef: CaptureController?
nonisolated(unsafe) var serverRef: InputDaemonServer?
let controller = CaptureController(
  seizer: LiveHIDSeizer(),
  clock: ContinuousClock(),
  onNotPermitted: {
    logger.error("Input Monitoring is missing for the input daemon; exiting so launchd relaunches it")
    controllerRef?.shutdown()
    if serverRef?.flush(timeout: flushTimeout) == false {
      logger.error("timed out sending the last messages to the helper")
    }
    exit(0)
  }
)
controllerRef = controller

// The daemon's own executable as it was at launch. An update or rebuild replaces it; the next
// helper connection then makes the daemon exit so launchd starts the new version.
let executablePath = Bundle.main.executablePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
let launchIdentity = executablePath.flatMap { ExecutableIdentity.current(path: $0) }
// Without a path or a launch identity there is nothing to compare with: every connection would
// count as changed and the daemon would exit in a loop. Log once and leave the check off.
if launchIdentity == nil {
  logger.error("own executable path or identity unavailable; not checking for updates on disk")
}

let server = InputDaemonServer(
  listener: NSXPCListener(machServiceName: AppIdentifiers.inputDaemonMachService),
  controller: controller,
  peerRequirement: PeerRequirement.helper(bundleID: AppIdentifiers.helperBundleID, teamID: teamID),
  executableChanged: {
    ExecutableIdentity.hasChanged(path: executablePath, since: launchIdentity)
  },
  onExecutableChanged: {
    // Runs on an XPC queue, outside the server's lock (`shutdown` and `flush` are safe to call
    // here). The rejected connection is not the client, so flushing reaches the current one.
    controllerRef?.shutdown()
    _ = serverRef?.flush(timeout: flushTimeout)
    exit(0)
  }
)
serverRef = server
server.resume()

signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
  logger.notice("SIGTERM, shutting down")
  controller.shutdown()
  // Lets the final `devicesChanged([])` reach the helper.
  _ = server.flush(timeout: flushTimeout)
  exit(0)
}
termSource.resume()

dispatchMain()
