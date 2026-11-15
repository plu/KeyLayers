#!/bin/sh
# Post-build phase of the Configurator target: embeds KeyLayersHelper.app as a login item and
# writes the launchd agent plist that SMAppService.agent(plistName:) registers. Also embeds the
# root KeyLayersInputDaemon and its launchd daemon plist (SMAppService.daemon(plistName:)).
set -eu

CONTENTS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
HELPER_SOURCE="${BUILT_PRODUCTS_DIR}/KeyLayersHelper.app"
LOGIN_ITEMS="${CONTENTS}/Library/LoginItems"
LAUNCH_AGENTS="${CONTENTS}/Library/LaunchAgents"
PLIST="${LAUNCH_AGENTS}/${HELPER_LAUNCHD_PLIST_NAME}"

if [ ! -d "${HELPER_SOURCE}" ]; then
  echo "error: ${HELPER_SOURCE} not found; KeyLayersHelper must be built before Configurator." >&2
  exit 1
fi

rm -rf "${LOGIN_ITEMS}/KeyLayersHelper.app"
# Recreate the directory so a renamed plist cannot linger across incremental builds.
rm -rf "${LAUNCH_AGENTS}"
mkdir -p "${LOGIN_ITEMS}" "${LAUNCH_AGENTS}"
ditto "${HELPER_SOURCE}" "${LOGIN_ITEMS}/KeyLayersHelper.app"

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${HELPER_BUNDLE_ID}</string>
	<key>BundleProgram</key>
	<string>Contents/Library/LoginItems/KeyLayersHelper.app/Contents/MacOS/KeyLayersHelper</string>
	<key>MachServices</key>
	<dict>
		<key>${HELPER_MACH_SERVICE_NAME}</key>
		<true/>
	</dict>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>${CONFIGURATOR_BUNDLE_ID}</string>
	</array>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST

plutil -lint "${PLIST}"

DAEMON_SOURCE="${BUILT_PRODUCTS_DIR}/KeyLayersInputDaemon"
HELPER_TOOLS="${CONTENTS}/Library/HelperTools"
LAUNCH_DAEMONS="${CONTENTS}/Library/LaunchDaemons"
DAEMON_PLIST="${LAUNCH_DAEMONS}/${INPUT_DAEMON_PLIST_NAME}"

if [ ! -f "${DAEMON_SOURCE}" ]; then
  echo "error: ${DAEMON_SOURCE} not found; KeyLayersInputDaemon must be built before Configurator." >&2
  exit 1
fi

rm -rf "${HELPER_TOOLS}" "${LAUNCH_DAEMONS}"
mkdir -p "${HELPER_TOOLS}" "${LAUNCH_DAEMONS}"
cp "${DAEMON_SOURCE}" "${HELPER_TOOLS}/KeyLayersInputDaemon"

# No RunAtLoad: launchd starts the daemon on demand when the helper connects to the Mach service.
cat > "${DAEMON_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${INPUT_DAEMON_LABEL}</string>
	<key>BundleProgram</key>
	<string>Contents/Library/HelperTools/KeyLayersInputDaemon</string>
	<key>MachServices</key>
	<dict>
		<key>${INPUT_DAEMON_MACH_SERVICE_NAME}</key>
		<true/>
	</dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>${CONFIGURATOR_BUNDLE_ID}</string>
	</array>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST

plutil -lint "${DAEMON_PLIST}"

# Debug builds: restart a running helper so it runs the code just embedded. launchd would otherwise
# keep the old process around until it exits. SIGTERM lets the helper release held keys and hand the
# keyboards back first. A stopped helper stays stopped, and Release builds (archives) never touch
# launchd.
if [ "${CONFIGURATION}" = "Debug" ]; then
  SERVICE="gui/$(id -u)/${HELPER_BUNDLE_ID}"
  if launchctl print "${SERVICE}" 2>/dev/null | grep -q "state = running"; then
    echo "Restarting ${SERVICE} to pick up the new helper build"
    launchctl kickstart -k "${SERVICE}" || echo "warning: could not restart ${SERVICE}" >&2
  fi
fi
