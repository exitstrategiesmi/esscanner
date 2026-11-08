  /* ---- LiDAR room scan (native shell bridge) ----
   * DROP-IN for js/app.js: this file is the canonical, complete version
   * of the scan block. To adopt it, replace the existing block in
   * js/app.js that starts with the "LiDAR room scan (native shell
   * bridge)" comment and runs through the end of bindScanButton (it is
   * the block immediately before bindRoomDetail) with the contents of
   * this file. Nothing in index.html changes: the block lives inside
   * the app.js IIFE, where DB, renderRoute and splitFtIn are in scope.
   * Full instructions: native-companion/web-bridge/INTEGRATION.md.
   *
   * Contract with the native shell (native-companion/ESScanner):
   *   web -> native : window.webkit.messageHandlers.scanRoom
   *                     .postMessage({ roomId: <number> })
   *                   (must be sent from the button's click handler)
   *   native -> web : window.handleScanResult(payload)
   *                   window.handleScanError({ code, message })
   *
   * Payload (all dimensions decimal feet, plus feet/inches splits):
   *   { version: 1, source: "roomplan", scannedAt: "<iso8601>",
   *     ceilingHeightFt: 8.02, ceilingHeight: { feet: 8, inches: 0.3 },
   *     walls:   [{ index, lengthFt, heightFt,
   *                 length: { feet, inches }, height: { feet, inches },
   *                 confidence: "low|medium|high",
   *                 openings: [<opening>, ...] }],
   *     windows: [{ kind: "window", widthFt, heightFt,
   *                 width: { feet, inches }, height: { feet, inches },
   *                 confidence, wallIndex }],
   *     doors:   [<opening, kind "door">],
   *     openings:[<opening, kind "opening">] }   // cased openings
   *
   * Merge rule (unchanged from the block this replaces): the scan
   * fills the room that was being edited when the button was tapped —
   * rect mode from the two longest walls + ceiling height when the
   * scan is solid, per-wall mode as the fallback — and the full raw
   * payload is kept on the room record as scanData. Every number
   * lands in the normal editable fields; scanning never locks a
   * measurement. Outside the shell (plain browser) the button
   * explains that scanning turns on in the app; manual entry is
   * completely unaffected. */
  var pendingScanRoomId = null;

  function scanAvailable() {
    return !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scanRoom);
  }

  function setFields(map) {
    Object.keys(map).forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      var parts = splitFtIn(map[id]);
      var inEl = document.getElementById(id + '-in');
      el.value = parts.ft === '' ? '' : parts.ft;
      if (inEl) inEl.value = parts.inch === '' ? '' : parts.inch;
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });
  }

  window.handleScanResult = async function (json) {
    var statusEl = document.getElementById('scan-status');
    var scan = null;
    try { scan = typeof json === 'string' ? JSON.parse(json) : json; } catch (e) { scan = null; }
    if (!scan || !pendingScanRoomId) {
      if (statusEl) statusEl.textContent = 'That scan did not come through. You can scan again or type the measurements in below.';
      return;
    }
    var rid = pendingScanRoomId;
    pendingScanRoomId = null;
    var walls = (scan.walls || []).filter(function (w) { return Number(w.lengthFt) > 0; });
    var heightFt = Number(scan.ceilingHeightFt) || 0;
    var windows = (scan.windows || []).length;
    var doors = (scan.doors || []).length;
    /* Keep the complete scan on the room: per-wall openings, feet/inch
     * splits and confidence survive even though the quick fields below
     * only use lengths, ceiling height and opening counts. */
    var patch = { scannedAt: Date.now(), scanData: scan };
    if (walls.length >= 2 && heightFt > 0) {
      var lens = walls.map(function (w) { return Number(w.lengthFt); }).sort(function (a, b) { return b - a; });
      patch.measureMode = 'rect';
      patch.lengthFt = lens[0];
      patch.widthFt = lens[1];
      patch.heightFt = heightFt;
      patch.windows = windows;
      patch.doors = doors;
    } else if (walls.length) {
      patch.walls = walls.slice(0, 4).map(function (w) {
        return { length: Number(w.lengthFt) || 0, height: Number(w.heightFt) || heightFt || 0 };
      });
      while (patch.walls.length < 4) patch.walls.push({});
      patch.measureMode = 'walls';
      patch.windows = windows;
      patch.doors = doors;
    }
    await DB.rooms.update(rid, patch).catch(function () {});
    renderRoute();
  };

  /* Called by the native shell when a scan cannot complete. err is
   * { code, message }; a bare string code is also accepted. Codes:
   * cancelled, camera-denied, lidar-unsupported, scan-failed,
   * encode-failed. The room is left exactly as it was. */
  window.handleScanError = function (err) {
    var code = typeof err === 'string' ? err : (err && err.code) || 'scan-failed';
    pendingScanRoomId = null;
    var statusEl = document.getElementById('scan-status');
    if (!statusEl) return;
    if (code === 'cancelled') {
      statusEl.textContent = 'Scan cancelled. You can scan again or type the measurements in below.';
    } else if (code === 'camera-denied') {
      statusEl.textContent = 'Camera access is off for the app. Turn it on in Settings to scan, or type the measurements in below.';
    } else if (code === 'lidar-unsupported') {
      statusEl.textContent = 'This device does not have a LiDAR scanner, so room scanning is not available on it. The measurements below work the same as always.';
    } else {
      statusEl.textContent = 'That scan did not come through. You can scan again or type the measurements in below.';
    }
  };

  function bindScanButton(roomId) {
    var btn = document.getElementById('scan-room');
    if (!btn) return;
    var statusEl = document.getElementById('scan-status');
    if (!scanAvailable()) {
      if (statusEl) statusEl.textContent = 'LiDAR scanning turns on in the Exit Strategies app. Manual measurements below work the same as always.';
      return;
    }
    btn.addEventListener('click', function () {
      pendingScanRoomId = Number(roomId);
      if (statusEl) statusEl.textContent = 'Opening the scanner. Walk the room slowly, then tap Done.';
      try {
        window.webkit.messageHandlers.scanRoom.postMessage({ roomId: Number(roomId) });
      } catch (e) {
        pendingScanRoomId = null;
        if (statusEl) statusEl.textContent = 'The scanner could not open. Manual measurements below still work.';
      }
    });
  }
