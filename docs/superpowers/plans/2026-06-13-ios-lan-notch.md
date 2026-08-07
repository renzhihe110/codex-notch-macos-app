# iOS LAN Notch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a first-version iOS companion app that connects to the existing macOS Codex Notch app over LAN, shows a real-time in-app notch, and mirrors active task status into Live Activity / Dynamic Island while the iOS app is running or foregrounded.

**Architecture:** Keep the macOS app as the only Codex state reader and add a small token-protected WebSocket publisher beside the existing `refreshStatus()` flow. Add a shared Codable payload module for the LAN protocol, then add an iOS app target and Live Activity widget target that consume the payload without reading Codex files directly. The MVP intentionally excludes APNs, Bonjour discovery, public network access, account login, and reliable killed-app delivery.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftPM, SwiftNIO + NIOWebSocket for the macOS WebSocket server, URLSessionWebSocketTask for the iOS client, CoreImage for QR code generation, ActivityKit + WidgetKit for Live Activity / Dynamic Island.

---

## Scope Notes

This plan covers one integrated feature. The macOS LAN publisher, iOS app, and Live Activity widget are separate build targets, but they are coupled by the shared protocol and must be planned together to avoid protocol drift.

Repository instruction override: do not add test code unless explicitly requested. Each task therefore includes manual verification and command checks only; do not add `Tests/` files during implementation unless the user changes that instruction. Do not auto-compile during planning; during implementation, run build commands only after the user explicitly allows compilation.

Existing uncommitted Swift changes are present in `Sources/CodexNotch/`. Implementation workers must inspect `git status --short` before every task and must not revert or overwrite unrelated local changes.

## File Structure

### Shared Protocol

- Create `Sources/CodexNotchShared/LANStatusPayload.swift`: Codable status enums, session payload, snapshot payload, pairing payload parser/formatter, and protocol version constants.
- Modify `Package.swift`: add a `CodexNotchShared` library product and target; add SwiftNIO package products to the macOS executable target.

### macOS App

- Create `Sources/CodexNotch/PairingStore.swift`: token persistence, token reset, pairing URL generation, host/port display values.
- Create `Sources/CodexNotch/LANStatusSnapshotMapper.swift`: converts `NotchState` to shared `LANStatusSnapshot` without sending `latestMessage`, complete cwd, jsonl events, or tool output.
- Create `Sources/CodexNotch/LANStatusServer.swift`: lifecycle API for starting, stopping, broadcasting snapshots, and reporting server state.
- Create `Sources/CodexNotch/LANWebSocketHandler.swift`: SwiftNIO channel handler for token validation and snapshot writes.
- Create `Sources/CodexNotch/QRCodeView.swift`: SwiftUI QR rendering from the pairing URL.
- Modify `Sources/CodexNotch/AppMain.swift`: own `PairingStore` and `LANStatusServer`, start/stop the server, broadcast snapshots from `refreshStatus()`, and pass pairing state into settings.
- Modify `Sources/CodexNotch/SettingsView.swift`: add the LAN pairing section with service state, address, QR code, token reset, and warning text.
- Modify `README.md`: document LAN companion MVP boundary and manual verification.

### iOS App And Widget

- Create `iOS/project.yml`: XcodeGen project definition for `CodexNotchIOS` app and `CodexNotchLiveActivity` widget extension, both depending on the local `CodexNotchShared` Swift package product.
- Create `iOS/CodexNotchIOS/App/CodexNotchIOSApp.swift`: SwiftUI app entry.
- Create `iOS/CodexNotchIOS/App/Info.plist`: local network usage description, camera usage description, custom URL scheme, Live Activities support key.
- Create `iOS/CodexNotchIOS/Connection/ConnectionStore.swift`: persisted pairing state and connection status.
- Create `iOS/CodexNotchIOS/Connection/QRCodeScannerView.swift`: camera scanner wrapper for pairing QR codes.
- Create `iOS/CodexNotchIOS/Connection/LANStatusClient.swift`: URLSessionWebSocketTask client with token URL, snapshot decode, disconnect, and retry state.
- Create `iOS/CodexNotchIOS/LiveActivity/CodexTaskActivityAttributes.swift`: ActivityKit attributes and content state that mirror the shared snapshot fields needed by the widget.
- Create `iOS/CodexNotchIOS/LiveActivity/CodexTaskActivityController.swift`: starts, updates, and ends the Live Activity from foreground snapshot changes.
- Create `iOS/CodexNotchIOS/Views/StatusDot.swift`: shared iOS status color view.
- Create `iOS/CodexNotchIOS/Views/InAppNotchView.swift`: in-app notch header.
- Create `iOS/CodexNotchIOS/Views/SessionListView.swift`: recent session list and empty state.
- Create `iOS/CodexNotchIOS/Views/ConnectionView.swift`: pairing, manual entry, reconnect, and error states.
- Create `iOS/CodexNotchIOS/Views/MainView.swift`: app composition and snapshot routing to Live Activity controller.
- Create `iOS/CodexNotchLiveActivity/CodexNotchLiveActivityBundle.swift`: WidgetKit bundle entry.
- Create `iOS/CodexNotchLiveActivity/CodexTaskLiveActivityWidget.swift`: lock screen, compact, minimal, and expanded Dynamic Island views.
- Create `iOS/CodexNotchLiveActivity/Info.plist`: widget extension metadata.

## Implementation Tasks

### Task 1: Shared LAN Protocol Model

**Files:**
- Create: `Sources/CodexNotchShared/LANStatusPayload.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Re-read current package shape**

Run: `sed -n '1,220p' Package.swift && find Sources -maxdepth 2 -type f | sort`

Expected: output shows the current macOS executable target and no existing `CodexNotchShared` target.

- [ ] **Step 2: Add a shared SwiftPM target**

Update `Package.swift` so it keeps the existing `CodexNotch` executable product, adds `.library(name: "CodexNotchShared", targets: ["CodexNotchShared"])`, adds `.target(name: "CodexNotchShared")`, and makes the `CodexNotch` executable target depend on `"CodexNotchShared"`.

Add SwiftNIO as a package dependency with products `NIO`, `NIOHTTP1`, and `NIOWebSocket` only on the `CodexNotch` executable target. Use the Apple SwiftNIO package URL `https://github.com/apple/swift-nio.git`.

- [ ] **Step 3: Add the shared payload file**

Create `Sources/CodexNotchShared/LANStatusPayload.swift` with Codable public models for `LANSessionStatus`, `LANSessionAttention`, `LANSessionPayload`, `LANStatusSnapshot`, and `LANPairingPayload`.

Required public fields: `LANStatusSnapshot.version`, `sentAt`, `aggregateStatus`, `lastUpdatedAt`, `sessions`, `errorMessage`; `LANSessionPayload.id`, `displayTitle`, `cwdHint`, `status`, `attention`, `activityText`, `updatedAt`; `LANPairingPayload.host`, `port`, `token`, `version`.

Required constants: protocol version `1` and URL scheme `codexnotch`.

- [ ] **Step 4: Verify shared payload shape manually**

Run: `sed -n '1,260p' Sources/CodexNotchShared/LANStatusPayload.swift`

Expected: the file contains only display-safe fields and no references to `latestMessage`, full `cwd`, jsonl event objects, user message body, assistant message body, or tool output.

- [ ] **Step 5: Commit after user confirmation**

Suggested message: `:sparkles: feat: add LAN status payload models`

Do not commit without explicit user confirmation if following the local commit rules.

### Task 2: macOS Pairing Store And Safe Snapshot Mapper

**Files:**
- Create: `Sources/CodexNotch/PairingStore.swift`
- Create: `Sources/CodexNotch/LANStatusSnapshotMapper.swift`

- [ ] **Step 1: Inspect current model fields**

Run: `sed -n '1,180p' Sources/CodexNotch/Models.swift`

Expected: output shows `CodexSession` and `NotchState` fields that can be mapped to the shared payload.

- [ ] **Step 2: Implement `PairingStore`**

Create `PairingStore` as an `ObservableObject` that owns a persisted random token, fixed default port, displayed host, and pairing URL. Store token under a new UserDefaults key such as `CodexNotch.lan.token`; use `UUID().uuidString.replacingOccurrences(of: "-", with: "")` or secure random bytes encoded as hex for the token.

Required API: `token`, `port`, `host`, `pairingURL`, `resetToken()`, and `isToken(_:)`.

- [ ] **Step 3: Implement safe snapshot mapper**

Create `LANStatusSnapshotMapper` with a static function that converts `NotchState` into `LANStatusSnapshot`. It must map only `session.id`, `session.displayTitle`, `session.cwdHint`, `session.status`, `session.attention`, `session.activityText`, and `session.updatedAt`.

Do not map `session.cwd`, `session.latestMessage`, `session.lastEvent`, `session.errorHint`, raw reader errors beyond the existing short `NotchState.errorMessage`, or any jsonl payload content.

- [ ] **Step 4: Verify privacy boundary by search**

Run: `rg -n "latestMessage|\\.cwd\\b|lastEvent|errorHint|payload|message" Sources/CodexNotch/PairingStore.swift Sources/CodexNotch/LANStatusSnapshotMapper.swift`

Expected: no result in `LANStatusSnapshotMapper.swift` except if a comment explicitly says a field is not mapped.

- [ ] **Step 5: Commit after user confirmation**

Suggested message: `:sparkles: feat: add LAN pairing state mapping`

### Task 3: macOS WebSocket Status Server

**Files:**
- Create: `Sources/CodexNotch/LANStatusServer.swift`
- Create: `Sources/CodexNotch/LANWebSocketHandler.swift`

- [ ] **Step 1: Inspect SwiftNIO dependency result**

Run: `sed -n '1,220p' Package.swift`

Expected: `CodexNotch` target has SwiftNIO products available.

- [ ] **Step 2: Implement server lifecycle**

Create `LANStatusServer` as a main-thread owned class with `start(pairingStore:)`, `stop()`, `broadcast(snapshot:)`, and published `state` describing `.stopped`, `.starting`, `.running(port:)`, or `.failed(message:)`.

Use `MultiThreadedEventLoopGroup(numberOfThreads: 1)`, bind to host `0.0.0.0`, and default to `PairingStore.port`. Keep a cached latest snapshot so newly connected clients receive a snapshot immediately after successful upgrade.

- [ ] **Step 3: Implement WebSocket upgrade and token validation**

Use SwiftNIO HTTP server upgrade with `NIOWebSocketServerUpgrader`. Validate the path `/stream`, query `token`, and query `v`. Reject invalid token or incompatible version before completing the WebSocket pipeline. Add `LANWebSocketHandler` only for accepted connections.

- [ ] **Step 4: Implement snapshot broadcast**

Encode `LANStatusSnapshot` with `JSONEncoder` using ISO8601 date encoding. Send text frames to all active channels. Remove closed or failed channels from the client list so stale iPhones do not accumulate.

- [ ] **Step 5: Add shutdown safety**

Ensure `stop()` closes the server channel, closes active client channels, and shuts down the event loop group gracefully. Ensure `applicationWillTerminate` can call it without blocking the app indefinitely.

- [ ] **Step 6: Verify server files manually**

Run: `rg -n "0\\.0\\.0\\.0|NIOWebSocketServerUpgrader|/stream|token|broadcast|shutdownGracefully" Sources/CodexNotch/LANStatusServer.swift Sources/CodexNotch/LANWebSocketHandler.swift`

Expected: output shows one bind host, a `/stream` path check, token validation, broadcast encode/send logic, and graceful shutdown.

- [ ] **Step 7: Commit after user confirmation**

Suggested message: `:sparkles: feat: add LAN WebSocket status server`

### Task 4: macOS App Wiring And Settings UI

**Files:**
- Modify: `Sources/CodexNotch/AppMain.swift`
- Modify: `Sources/CodexNotch/SettingsView.swift`
- Create: `Sources/CodexNotch/QRCodeView.swift`

- [ ] **Step 1: Inspect current app delegate and settings initializer**

Run: `sed -n '1,220p' Sources/CodexNotch/AppMain.swift && sed -n '1,220p' Sources/CodexNotch/SettingsView.swift`

Expected: `SettingsView` currently receives hot key and capsule settings only.

- [ ] **Step 2: Wire LAN state into `AppDelegate`**

Add `PairingStore` and `LANStatusServer` properties. Start the server in `applicationDidFinishLaunching`, stop it in `applicationWillTerminate`, and call `lanStatusServer.broadcast(snapshot:)` after each successful `StatusMapper.map(snapshot:)` result in `refreshStatus()`.

Keep the existing notch window, status bar item, local notifier, and completion popup behavior unchanged.

- [ ] **Step 3: Pass pairing and server state to settings**

Update `SettingsView` initializer and `SettingsWindowController` to receive the pairing store and LAN server state object. Increase settings window height enough for the new section.

- [ ] **Step 4: Add QR code view**

Create `QRCodeView` using CoreImage QR generation and SwiftUI image rendering. The view takes a string and fixed display size. If QR generation fails, show a short Chinese fallback text with the manual pairing URL.

- [ ] **Step 5: Add settings LAN section**

Add a section titled `局域网 iOS 连接` with status text, host/port, QR code, token reset button, and warning copy: `仅同一局域网内可用；第一版只保证 iOS App 前台实时同步。`

Token reset must call `PairingStore.resetToken()` and should cause existing WebSocket clients to fail their next authorization or be disconnected by the server.

- [ ] **Step 6: Verify UI copy and wiring by search**

Run: `rg -n "局域网 iOS 连接|QRCodeView|PairingStore|LANStatusServer|broadcast\\(|resetToken" Sources/CodexNotch`

Expected: output shows app delegate ownership, settings section, QR rendering, broadcast call, and token reset action.

- [ ] **Step 7: Commit after user confirmation**

Suggested message: `:sparkles: feat: expose LAN pairing in settings`

### Task 5: iOS Project Scaffold

**Files:**
- Create: `iOS/project.yml`
- Create: `iOS/CodexNotchIOS/App/CodexNotchIOSApp.swift`
- Create: `iOS/CodexNotchIOS/App/Info.plist`
- Create: `iOS/CodexNotchLiveActivity/CodexNotchLiveActivityBundle.swift`
- Create: `iOS/CodexNotchLiveActivity/Info.plist`
- Modify: `.gitignore`
- Modify: `README.md`

- [ ] **Step 1: Choose generated project boundary**

Use XcodeGen for the iOS Xcode project to avoid hand-maintaining a large `.pbxproj`. Commit `iOS/project.yml`; do not commit generated `iOS/CodexNotchIOS.xcodeproj` in the MVP.

- [ ] **Step 2: Add XcodeGen ignore rule**

Add `iOS/*.xcodeproj/` to `.gitignore`. Keep existing `.build/`, `dist/`, and `.superpowers/` rules intact.

- [ ] **Step 3: Create `project.yml`**

Define an iOS app target `CodexNotchIOS` with bundle id `local.codex.notch.ios`, deployment target iOS 17.0 or newer, SwiftUI lifecycle, and a widget extension target `CodexNotchLiveActivity` with bundle id `local.codex.notch.ios.liveactivity`.

Add the local package dependency at `../` and link product `CodexNotchShared` into both iOS targets.

- [ ] **Step 4: Add minimal app entry**

Create `CodexNotchIOSApp.swift` with a SwiftUI `@main` app that shows `MainView` once it exists. During this scaffold task, use a temporary small view that says `Codex Notch` so the target has an entry point.

- [ ] **Step 5: Add iOS app plist**

Add `NSLocalNetworkUsageDescription` with a clear Chinese explanation that the app connects to the user's Mac on the local network to display Codex task status. Add `NSCameraUsageDescription` for QR scanning. Add `NSSupportsLiveActivities` set to true. Add URL scheme `codexnotch`.

- [ ] **Step 6: Add widget extension entry files**

Create the WidgetKit bundle entry and widget extension plist. The widget implementation can be a minimal shell in this task and becomes complete in Task 9.

- [ ] **Step 7: Verify scaffold files**

Run: `find iOS -maxdepth 4 -type f | sort && rg -n "CodexNotchIOS|CodexNotchLiveActivity|NSSupportsLiveActivities|NSLocalNetworkUsageDescription|NSCameraUsageDescription|CodexNotchShared" iOS .gitignore README.md`

Expected: output shows the project spec, app entry, widget entry, required privacy strings, Live Activity key, and local shared package dependency.

- [ ] **Step 8: Commit after user confirmation**

Suggested message: `:sparkles: feat: scaffold iOS companion targets`

### Task 6: iOS Pairing And Connection State

**Files:**
- Create: `iOS/CodexNotchIOS/Connection/ConnectionStore.swift`
- Create: `iOS/CodexNotchIOS/Connection/QRCodeScannerView.swift`
- Create: `iOS/CodexNotchIOS/Views/ConnectionView.swift`
- Modify: `iOS/CodexNotchIOS/Views/MainView.swift`

- [ ] **Step 1: Create connection store**

Create an `ObservableObject` that stores `LANPairingPayload` in UserDefaults, exposes connection status cases for not paired, connecting, connected, offline, authentication failed, incompatible protocol, and service unavailable, and provides clear actions for save pairing, clear pairing, and manual update.

- [ ] **Step 2: Create QR scanner wrapper**

Use `AVFoundation` through a `UIViewControllerRepresentable` scanner. On recognized QR text, parse `LANPairingPayload` from the shared model and save it through `ConnectionStore`.

- [ ] **Step 3: Create manual entry form**

Add a SwiftUI form for host, port, and token. Validate that host is non-empty, port is a valid integer in a normal TCP port range, token is non-empty, and protocol version is 1.

- [ ] **Step 4: Create connection view states**

`ConnectionView` must show QR scanning entry, manual entry fallback, current paired Mac address, reconnect action, and clear pairing action. Error text must distinguish local network permission denied, offline, auth failed, incompatible protocol, and service unavailable when the client provides those statuses.

- [ ] **Step 5: Verify state names and UI copy**

Run: `rg -n "notPaired|connecting|connected|offline|authenticationFailed|incompatibleProtocol|serviceUnavailable|扫码|手动输入|重新连接|清除配对" iOS/CodexNotchIOS`

Expected: output shows all required connection states and Chinese UI copy.

- [ ] **Step 6: Commit after user confirmation**

Suggested message: `:sparkles: feat: add iOS pairing flow`

### Task 7: iOS WebSocket Client And Snapshot Store

**Files:**
- Create: `iOS/CodexNotchIOS/Connection/LANStatusClient.swift`
- Modify: `iOS/CodexNotchIOS/Connection/ConnectionStore.swift`
- Modify: `iOS/CodexNotchIOS/Views/MainView.swift`

- [ ] **Step 1: Implement URL builder**

Build WebSocket URLs as `ws://<host>:<port>/stream?token=<token>&v=1`. Percent-encode token through `URLComponents` rather than manual string concatenation.

- [ ] **Step 2: Implement WebSocket lifecycle**

Use `URLSessionWebSocketTask` with explicit connect, receive loop, disconnect, and retry methods. Decode incoming text messages as `LANStatusSnapshot`. Publish latest snapshot and connection status on the main actor.

- [ ] **Step 3: Implement retry rules**

On transient network errors, set status to offline and retry with bounded exponential backoff. On auth failure or incompatible protocol, stop automatic retry and ask the user to re-pair.

- [ ] **Step 4: Wire app lifecycle**

Connect when `MainView` appears and a pairing exists. Disconnect when the app moves to background if foreground-only behavior is required for the MVP. Reconnect when the app returns to active.

- [ ] **Step 5: Verify client safety**

Run: `rg -n "URLSessionWebSocketTask|URLComponents|receive|retry|authenticationFailed|incompatibleProtocol|disconnect" iOS/CodexNotchIOS/Connection iOS/CodexNotchIOS/Views/MainView.swift`

Expected: output shows URLComponents-based URL construction, receive loop, bounded retry, and explicit disconnect.

- [ ] **Step 6: Commit after user confirmation**

Suggested message: `:sparkles: feat: subscribe to LAN status snapshots`

### Task 8: iOS In-App Notch And Session List

**Files:**
- Create: `iOS/CodexNotchIOS/Views/StatusDot.swift`
- Create: `iOS/CodexNotchIOS/Views/InAppNotchView.swift`
- Create: `iOS/CodexNotchIOS/Views/SessionListView.swift`
- Create: `iOS/CodexNotchIOS/Views/MainView.swift`

- [ ] **Step 1: Create status dot**

Map shared status values to red, yellow, and green SwiftUI colors. Keep the component fixed-size so changing text does not resize the notch.

- [ ] **Step 2: Create in-app notch header**

Render a black top notch panel with status dot, current prioritized session title, and completed count. Prioritize red sessions, then yellow sessions, then the latest green session. Keep text single-line and truncating.

- [ ] **Step 3: Create session list**

Render recent sessions from the latest snapshot with title, `cwdHint`, status label, attention label, and `activityText`. Show an empty state when there are no sessions.

- [ ] **Step 4: Compose main view**

Show `ConnectionView` when not paired. Show `InAppNotchView`, connection status, last update time, and `SessionListView` when paired. Show offline or service error banners without covering the notch.

- [ ] **Step 5: Verify UI file boundaries**

Run: `find iOS/CodexNotchIOS/Views -maxdepth 1 -type f -print | sort && rg -n "InAppNotchView|SessionListView|StatusDot|ConnectionView|activityText|cwdHint" iOS/CodexNotchIOS/Views`

Expected: each view has a focused file and the UI uses display-safe shared payload fields only.

- [ ] **Step 6: Commit after user confirmation**

Suggested message: `:sparkles: feat: add iOS notch dashboard`

### Task 9: Live Activity And Dynamic Island

**Files:**
- Create: `iOS/CodexNotchIOS/LiveActivity/CodexTaskActivityAttributes.swift`
- Create: `iOS/CodexNotchIOS/LiveActivity/CodexTaskActivityController.swift`
- Modify: `iOS/CodexNotchIOS/Views/MainView.swift`
- Modify: `iOS/CodexNotchLiveActivity/CodexTaskLiveActivityWidget.swift`

- [ ] **Step 1: Define ActivityKit attributes**

Create attributes with stable task identity and content state containing display title, project hint, aggregate status, attention label, completed count, total count, and updated time.

- [ ] **Step 2: Implement activity controller**

Start a Live Activity only from foreground snapshot changes when there is at least one red or yellow session. Update the active activity when the prioritized session or aggregate status changes. End the activity when all sessions are green or the connection is intentionally cleared.

- [ ] **Step 3: Wire snapshot updates**

In `MainView`, pass latest snapshots to the activity controller after the WebSocket client publishes them. Do not start a Live Activity from background-only callbacks.

- [ ] **Step 4: Implement widget UI**

Implement lock screen, Dynamic Island compact, minimal, and expanded regions. Use black-background-friendly white text, status dot color, short title, attention label, project hint, and completion count. Do not show raw user or assistant text.

- [ ] **Step 5: Verify Live Activity references**

Run: `rg -n "ActivityKit|WidgetKit|ActivityConfiguration|DynamicIsland|compactLeading|compactTrailing|minimal|expanded|NSSupportsLiveActivities" iOS`

Expected: output shows ActivityKit attributes/controller, WidgetKit configuration, all Dynamic Island presentations, and the Live Activity plist key.

- [ ] **Step 6: Commit after user confirmation**

Suggested message: `:sparkles: feat: add Live Activity status surface`

### Task 10: Documentation And Manual Acceptance

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/verification/2026-06-13-ios-lan-notch-manual.md`

- [ ] **Step 1: Update README**

Document how to enable the macOS LAN status service, how to scan the QR code, how to use manual host/port/token entry, and the MVP limitation that foreground iOS updates are supported while killed-app delivery is not.

- [ ] **Step 2: Add manual verification checklist**

Document these checks: Mac settings shows QR and address; iPhone scans and connects; foreground state changes update the iOS notch; red/yellow sessions start or update Live Activity; stopping Mac service shows offline; resetting token invalidates old connection; transmitted payload excludes full cwd and conversation text.

- [ ] **Step 3: Verify no accidental privacy leak**

Run: `rg -n "latestMessage|lastEvent|errorHint|\\.cwd\\b|payload|message" Sources/CodexNotch iOS Sources/CodexNotchShared`

Expected: any result in LAN protocol, server, or iOS files must be reviewed. Display payload code must not transmit full cwd, user text, assistant text, raw event payload, or tool output.

- [ ] **Step 4: Verify generated project instructions**

Run: `rg -n "XcodeGen|project.yml|局域网|二维码|Dynamic Island|Live Activity|前台" README.md docs/superpowers`

Expected: README and docs explain how to generate/open the iOS project and clearly state the foreground-only boundary.

- [ ] **Step 5: Build verification only after user approval**

Do not run compilation unless the user explicitly approves it. If approved later, use `swift build` for macOS package sanity and the generated Xcode project build command for the iOS app and widget.

- [ ] **Step 6: Commit after user confirmation**

Suggested message: `:memo: docs: document iOS LAN companion workflow`

## Manual End-To-End Acceptance

- macOS settings page shows service state, host, port, QR code, and token reset.
- iOS app can scan QR and save pairing.
- iOS app can manually enter host, port, and token.
- iOS app foreground WebSocket receives snapshots and updates the in-app notch.
- Red or yellow sessions appear before green sessions in the iOS notch priority.
- Live Activity starts for active sessions and shows lock screen plus Dynamic Island UI.
- Closing the macOS service or leaving the LAN shows offline state on iOS.
- Resetting the macOS token invalidates old iOS connections until the device re-pairs.
- Shared payload inspection confirms no complete conversation text, tool output, raw jsonl events, or full cwd is sent.

## Source References

- Design spec: `docs/superpowers/specs/2026-06-13-ios-lan-notch-design.md`
- Apple ActivityKit: https://developer.apple.com/documentation/ActivityKit/
- Apple Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple URLSessionWebSocketTask: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask
- Apple TN3179 Understanding local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Apple SwiftNIO: https://github.com/apple/swift-nio
