# Web bridge integration — where scan-bridge.js hooks in

**Status of the dev build today:** `~/workspace/estimator-dev/js/app.js` already
contains a working scan block (search for `LiDAR room scan (native shell bridge)`,
around line 2106). It implements the same contract the native shell is built
against, so **the native companion works with the dev build as-is**. This
drop-in is the canonical, slightly richer version of that block. Adopting it is
optional polish, not a prerequisite — and nothing here touches the production
PWA in `~/workspace/estimator-app/`.

## What the drop-in adds over the block already in app.js

1. `window.handleScanError({ code, message })` — the native shell calls this
   when a scan is cancelled, camera permission is denied, the device has no
   LiDAR, or processing fails. The current app.js block has no error callback,
   so today those cases end silently on the web side. With the drop-in, each
   one leaves a clear message in the `#scan-status` line and never touches the
   room's data.
2. The full raw payload is stored on the room record as `patch.scanData`
   (per-wall openings, feet/inches splits, confidence), instead of being
   reduced to lengths + counts and discarded.
3. Everything else — handler name, merge semantics, status texts — is
   byte-for-byte the same behavior as the current block.

## Exactly how to adopt it (one edit, inside app.js only)

1. Open `~/workspace/estimator-dev/js/app.js`.
2. Find the block that begins with the comment
   `/* ---- LiDAR room scan (native shell bridge) ----`
   and ends with the closing brace of `function bindScanButton(roomId) { ... }`.
   It sits **immediately before** `function bindRoomDetail(estimateId, roomId)`.
3. Replace that whole block with the contents of `scan-bridge.js` (this folder).
   Keep it at the same place, **inside the app.js IIFE** — the block uses `DB`
   (global from js/db.js), `renderRoute()`, and `splitFtIn()`, all of which are
   in scope there. Do not load it as a separate `<script>`; outside the IIFE
   `renderRoute` and `splitFtIn` are not reachable.
4. No changes to `index.html`: the button markup (`#scan-room`,
   `#scan-status`) is already emitted by the room view, and `bindRoomDetail`
   already calls `bindScanButton(roomId)`.
5. No changes to sw.js / manifest.json. The native shell loads the estimator
   over HTTPS from `AppConfig.estimatorURL`; the service worker behaves the
   same inside WKWebView.
6. Re-run the dev build's suites from `~/workspace/estimator-dev/`:
   `node test-phase1.js` and `node test-phase1b.js` — both must stay green.

## The contract both sides must keep

| Direction | Call | Notes |
|---|---|---|
| web → native | `window.webkit.messageHandlers.scanRoom.postMessage({ roomId })` | Must be sent from the button's click handler. `roomId` is informational; the page tracks the pending room itself. |
| native → web | `window.handleScanResult(payload)` | Payload object (a JSON string is also accepted). Shape documented at the top of `scan-bridge.js` and produced by `CapturedRoomConverter.swift`. |
| native → web | `window.handleScanError({ code, message })` | Codes: `cancelled`, `camera-denied`, `lidar-unsupported`, `scan-failed`, `encode-failed`. |

If any name in this table ever changes, it must change in `app.js`
(`scanAvailable`, `bindScanButton`), in `AppConfig.swift` (`scanHandlerName`),
and in `ShellViewController.swift` (the two `evaluate(...)` calls) in the same
commit — the bridge fails silently otherwise.
