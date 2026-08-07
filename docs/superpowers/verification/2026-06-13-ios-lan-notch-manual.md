# iOS LAN Notch Manual Verification

## Scope

This checklist verifies the MVP described in `docs/superpowers/specs/2026-06-13-ios-lan-notch-design.md`: local-network foreground sync, QR token pairing, iOS in-app notch, and Live Activity / Dynamic Island status display.

## macOS Checks

- Open Codex Notch settings and confirm `局域网 iOS 连接` is visible.
- Confirm the settings section shows service status, host, port, QR code, token, service start/stop, and `重置 token`.
- Confirm the LAN service does not change the existing notch entry, capsule mode, local notifications, or completion popup behavior.
- Confirm `http://<mac-host>:48573/health` returns a small health response when the Mac and client are on the same LAN.

## iOS Pairing Checks

- Generate the iOS project from `iOS/project.yml` with XcodeGen.
- Launch the iOS app and scan the QR code from the Mac settings page.
- Confirm manual host, port, and token entry works when camera access is unavailable.
- Deny local network permission once and confirm the app surfaces a clear connection problem instead of hiding it.

## Foreground Sync Checks

- With the iOS app foregrounded, start or resume a Codex task on the Mac.
- Confirm the iOS in-app notch updates status and completion count after the Mac snapshot changes.
- Confirm red sessions appear before yellow sessions, and yellow sessions appear before all-green sessions.
- Stop the Mac service or leave the LAN and confirm iOS shows an offline state with a reconnect action.
- Reset the macOS token and confirm the old iOS connection no longer receives updates until the device re-pairs.

## Live Activity Checks

- With at least one red or yellow session, confirm a Live Activity starts from the foreground iOS app.
- Confirm Dynamic Island compact, minimal, expanded, and lock-screen views show only title, project hint, status, attention label, and completion count.
- Confirm all-green snapshots or clearing pairing ends the current Live Activity.

## Privacy Checks

- Inspect LAN payload code and confirm it does not transmit full cwd, `latestMessage`, raw jsonl payloads, user message bodies, assistant message bodies, or tool output.
- Confirm iOS UI and Live Activity only render shared payload fields: `displayTitle`, `cwdHint`, `status`, `attention`, `activityText`, `updatedAt`, and completion counts.
