# ESScanner — native RoomPlan companion for the Exit Strategies estimator

A thin native iOS shell that wraps the existing web estimator in a
WKWebView and adds the one capability a web page cannot have on iOS:
LiDAR room scanning through Apple's RoomPlan. Inside the estimator, the
**Scan Room with LiDAR** button calls the native bridge; the shell
presents RoomPlan capture; when the scan finishes, structured
measurements (walls, ceiling height, doors, windows, openings) flow
back into the page and land in the room that was being edited. The
native side only supplies measurements — every number stays editable
in the web UI, and pricing/scope/proposal logic is never touched here.

This project supersedes the one-file prototype in
`~/workspace/estimator-dev/native-shell/`, which remains in place for
reference. Architecture follows `../NATIVE-COMPANION-RESEARCH.md`
(Architecture C: WKWebView shell + in-memory bridge).

## ⚠️ First compile happens in the cloud

Swift cannot be compiled on Sam's Linux VM (Xcode is macOS-only), so
**this code has never been compiled**. It is written as standard,
idiomatic Swift/UIKit with no third-party dependencies, and the Xcode
project file was machine-checked for internal consistency (every
referenced object and file verified) — but the first real compile is
the GitHub Actions run described below, and a short fix cycle on that
first run is normal. See `BUILD-READINESS-CHECKLIST.md`.

## Layout

```
native-companion/                  ← treat this folder as the repo root
├── ESScanner.xcodeproj/           Xcode project (target: ESScanner)
│   └── xcshareddata/xcschemes/    shared scheme "ESScanner"
├── ESScanner/
│   ├── AppDelegate.swift          @main, UIKit lifecycle
│   ├── SceneDelegate.swift        window + root controller (no storyboard)
│   ├── AppConfig.swift            estimator URL + bridge handler name
│   ├── ShellViewController.swift  WKWebView host, bridge, scan flow,
│   │                              camera-permission and error delivery
│   ├── RoomScanViewController.swift  RoomPlan capture screen + delegate
│   ├── CapturedRoomConverter.swift   CapturedRoom → estimator JSON
│   ├── ScanModels.swift           the payload contract (Codable)
│   ├── Info.plist                 incl. NSCameraUsageDescription
│   └── Assets.xcassets/           AppIcon (placeholder) + AccentColor
├── web-bridge/
│   ├── scan-bridge.js             drop-in replacement for the scan
│   │                              block already inside js/app.js
│   └── INTEGRATION.md             exact hook points in the web build
├── .github/workflows/
│   └── build-unsigned.yml         the $0 cloud build (below)
├── BUILD-READINESS-CHECKLIST.md
└── README.md
```

## Architecture choices

- **UIKit, not SwiftUI.** The app is a single full-screen view
  controller. A pure UIKit lifecycle keeps the WKWebView and its
  script-message handler alive for exactly the window's lifetime and
  avoids `UIViewControllerRepresentable` coordinator plumbing — fewer
  moving parts for a first cloud build. RoomPlan's `RoomCaptureView`
  is a UIKit view either way, so nothing is wrapped or bridged.
- **In-memory bridge, no backend.** Scan results travel
  `WKScriptMessageHandler` → `evaluateJavaScript` inside the app.
  The scan-session token endpoints sketched in the research doc were
  only needed for the two-app URL-handoff design; this shell doesn't
  need them, so there is no server work and no PII in any payload
  (the payload is geometry only).
- **Weak handler proxy.** `WKUserContentController` retains handlers
  strongly; `WeakScriptMessageHandler` in `ShellViewController.swift`
  is the standard fix for the resulting retain cycle.
- **Manual signing, no team.** `CODE_SIGN_STYLE = Manual` and an empty
  `DEVELOPMENT_TEAM` keep the project buildable unsigned in CI.
  SideStore applies the owner's free-Apple-ID signature on the phone.

## The bridge contract

| Direction | Call |
|---|---|
| web → native | `window.webkit.messageHandlers.scanRoom.postMessage({ roomId })` |
| native → web | `window.handleScanResult(<ScanPayload JSON>)` |
| native → web | `window.handleScanError(<{ code, message } JSON>)` |

Payload fields the web side reads today: `ceilingHeightFt`,
`walls[].lengthFt/heightFt`, `windows.length`, `doors.length`. The
payload additionally carries feet/inches splits, per-wall openings,
generic cased openings, and RoomPlan confidence per surface — all
documented in `ScanModels.swift` and at the top of
`web-bridge/scan-bridge.js`. The dev build's `js/app.js` already
implements this contract; `web-bridge/INTEGRATION.md` describes the
optional drop-in that adds error handling and raw-scan storage.

## Minimum iOS: 17.0 — and why

- RoomPlan's base API needs iOS 16, but this project targets the
  current, stable API surface: the `RoomCaptureView` delegate flow
  used here, plus iOS 17 additions on `CapturedRoom` (floors,
  sections, `polygonCorners`) that the converter can grow into
  without a deployment bump.
- Both target devices clear it easily: the iPhone 18 Pro Max ships on
  a current iOS, and the LiDAR iPad Pro (5th gen) updates well past
  iOS 17. The oldest LiDAR hardware (iPhone 12 Pro, 2020 iPad Pro)
  also runs iOS 17, so the floor costs no device coverage.
- Devices without LiDAR still install and run the estimator; the
  shell detects `RoomCaptureSession.isSupported == false` and reports
  `lidar-unsupported` to the page, which keeps manual entry.

## Permissions, entitlements, capabilities

- **Camera:** `NSCameraUsageDescription` is in `Info.plist` (required —
  RoomPlan capture fails without it). The shell also checks
  `AVCaptureDevice.authorizationStatus` before presenting the scanner
  so a denied permission produces a clear in-page message and a
  Settings shortcut instead of a dead capture screen.
- **Entitlements: none.** RoomPlan needs no entitlement, no
  capability tab entries, and no `Info.plist` key beyond the camera
  usage string. (This corrects the earlier `native-shell/` README,
  which mentioned adding a "RoomPlan capability/entitlement" — no
  such thing exists.)
- **ATS:** defaults apply; the estimator is HTTPS-only, so no
  transport exceptions are declared.
- The bundle ID is `com.exitstrategiesmi.estimator` (placeholder-grade:
  it only needs to be unique; SideStore re-signing does not care).

## How the build runs ($0 route)

Verified in `../research/MAC-FREE-BUILD-ROUTES-2026-11-07.md`:

1. Push this folder as a GitHub repository (public = free unlimited
   standard macOS runners; private on GitHub Free includes ~$12/mo of
   compute, macOS at $0.062/min — one build is ~5–15 min).
2. The `Build unsigned IPA` workflow (`.github/workflows/build-unsigned.yml`)
   runs on a macOS runner: `xcodebuild build` with
   `CODE_SIGNING_ALLOWED=NO`, then zips the `.app` into
   `ESScanner-unsigned.ipa` and uploads it as a workflow artifact.
   It builds with `-target` instead of `-scheme` so CI never depends
   on the shared scheme being picked up.
3. Download the artifact, get the `.ipa` onto the iPhone, and install
   with **SideStore**, which signs it with the owner's free Apple ID.
   Free provisioning expires every 7 days; SideStore refreshes the
   signature in the background over Wi-Fi. RoomPlan/LiDAR work fully
   under free provisioning — the 7-day signature is the only
   compromise. A permanent install would require Apple's $99/yr
   Developer Program (owner's decision; zero-spending rule applies).

## ⚠️ Open item — SideStore's one-time setup (flagged, not solved)

SideStore's **first** installation on the phone requires a computer
**once** — a Mac *or a Windows PC* — to generate and place its pairing
file (current tooling: iloader). After that one-time setup, installs
and signature refreshes happen entirely on the phone. Whether that
one-time access is a borrowed PC, a library machine, or the same
session that someday provides a Mac is an owner logistics decision;
nothing in this project can remove the requirement, and it is the
only step of the $0 route that cannot be done from the phone alone.

## Before the first build

- Confirm `AppConfig.estimatorURL` points at the live served path of
  the estimator (it currently uses the staging quotes worker's
  `/estimator/` path, inherited from the prototype). Production is a
  one-line change, made only on the owner's approval.
- The app icon is a placeholder (brand navy/red blocks). Swap
  `ESScanner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` for
  real art any time — no code depends on it.
- Field-validate after install: scan 3 real rooms (rectangular,
  L-shaped, furnished), compare every wall against a tape/laser, and
  record errors before trusting scan numbers in a priced proposal.
  Apple publishes no RoomPlan accuracy guarantee; third-party tests
  suggest roughly ±1–3 in per wall.
