# Build-readiness checklist — ESScanner native companion

State as of Nov 7, 2026: **code-complete, never compiled.** Swift/Xcode
do not exist on Sam's VM; the first compile is the cloud workflow run.
Everything below is ordered so the first run has the fewest surprises.

## Verified here (no Mac needed)

- [x] Xcode project internal consistency: all 32 object IDs in
      `project.pbxproj` are defined and cross-referenced correctly
      (machine-checked); every file the project references exists.
- [x] Bridge contract matches the web build exactly: handler name
      `scanRoom`, message `{ roomId }`, callback
      `window.handleScanResult`, payload keys `ceilingHeightFt`,
      `walls[].lengthFt/heightFt`, `windows`, `doors`
      (checked against `~/workspace/estimator-dev/js/app.js`).
- [x] Info.plist contains `NSCameraUsageDescription` and a scene
      manifest whose configuration name ("Default Configuration") and
      delegate class (`SceneDelegate`) match the Swift code.
- [x] App icon asset is a real 1024×1024 PNG; asset catalog JSON parses.
- [x] Workflow YAML structure reviewed; unsigned-build flags set
      (`CODE_SIGNING_ALLOWED=NO`), artifact path matches the
      `-derivedDataPath` the workflow passes to xcodebuild.

## Owner / pre-build decisions

- [ ] Confirm the estimator URL in `ESScanner/AppConfig.swift`
      (currently the staging quotes worker `/estimator/` path) is the
      live served path for the first field test. Production switch =
      owner approval only.
- [ ] Confirm the GitHub account/repo to host the project (public repo
      = free runners; nothing in the project is secret — the estimator
      URL is already public-facing).
- [ ] Plan the one-time computer access SideStore needs for its first
      install (Mac or Windows PC, once). See README "Open item".

## First cloud build

- [ ] Push `native-companion/` as the repository root.
- [ ] Run the **Build unsigned IPA** workflow (Actions tab →
      Run workflow, or push to `main`).
- [ ] Confirm the run produces `ESScanner-unsigned.ipa` as an artifact.
- [ ] Download the artifact; install via SideStore on the
      iPhone 18 Pro Max (after SideStore's one-time setup).

## Likely first-build fix candidates (watch for these)

- [ ] Runner toolchain drift: workflow pins `macos-15` (Xcode 16.x).
      If GitHub has retired the image, switch `runs-on` to
      `macos-latest` — no project change needed.
- [ ] If `xcodebuild` complains about the hand-authored project file,
      opening the project once in any Xcode and re-saving normalizes
      it; the source files need no changes for that.
- [ ] If the asset catalog step warns about the placeholder icon,
      it is cosmetic for a sideloaded build — replace the PNG when
      real icon art exists.

## First on-device checks

- [ ] App launches; estimator loads inside the shell (sign-in/drafts
      persist across relaunch — persistent WKWebView store).
- [ ] Room view shows the normal Scan Room button behavior; tapping it
      raises the iOS camera-permission prompt the first time.
- [ ] Deny the permission once: page shows the camera-off message,
      alert offers Settings; manual entry still works.
- [ ] Scan a rectangular room → Done → measurements land in the room
      that was open, in the normal editable fields.
- [ ] Cancel mid-scan: page shows the cancelled message; the room's
      previous numbers are untouched.
- [ ] Tape-check every wall of 3 rooms (rectangular, L-shaped,
      furnished) and record scan-vs-tape errors before any scanned
      number is trusted in a priced proposal.
