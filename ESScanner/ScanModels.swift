//  ScanModels.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  The JSON payload handed back to the web estimator through
//  window.handleScanResult(...). The field names are a contract with
//  the web side — js/app.js reads exactly:
//
//      scan.ceilingHeightFt            (number, decimal feet)
//      scan.walls[]                    .lengthFt / .heightFt
//      scan.windows.length             (count)
//      scan.doors.length               (count)
//
//  Everything else (feet/inches splits, per-wall openings, confidence,
//  generic openings) is additive: the web callback ignores fields it
//  does not know, and the full payload is also stored on the room
//  record as scanData so nothing the scanner saw is thrown away.
//  All measurements stay editable in the web UI — this payload only
//  supplies them.

import Foundation

/// A measurement split into whole feet + remaining inches,
/// matching the estimator's paired feet/inches input fields.
struct FeetInches: Codable {
    let feet: Int
    /// Remaining inches, rounded to the nearest tenth
    /// (RoomPlan's real-world accuracy is ±1–3 in, so tenths
    /// are already finer than the scan can honestly claim).
    let inches: Double

    init(decimalFeet: Double) {
        let totalInches = max(0, decimalFeet) * 12
        var wholeFeet = Int(totalInches / 12)
        var remainder = totalInches - Double(wholeFeet) * 12
        remainder = (remainder * 10).rounded() / 10
        if remainder >= 12 {          // rounding carried into the next foot
            wholeFeet += 1
            remainder = 0
        }
        feet = wholeFeet
        inches = remainder
    }
}

/// One door, window, or cased opening found in the scan.
struct ScanOpening: Codable {
    /// "door" | "window" | "opening" (a cased opening with no door slab)
    let kind: String
    let widthFt: Double
    let heightFt: Double
    let width: FeetInches
    let height: FeetInches
    /// RoomPlan detection confidence: "low" | "medium" | "high"
    let confidence: String
    /// Index of the wall (in ScanPayload.walls) this opening sits in,
    /// or nil when RoomPlan did not link it to a wall.
    let wallIndex: Int?
}

/// One wall segment found in the scan.
struct ScanWall: Codable {
    let index: Int
    let lengthFt: Double
    let heightFt: Double
    let length: FeetInches
    let height: FeetInches
    /// RoomPlan detection confidence: "low" | "medium" | "high"
    let confidence: String
    /// Openings hosted on this wall (subset of the payload-level lists).
    let openings: [ScanOpening]
}

/// The complete scan result for one room.
struct ScanPayload: Codable {
    /// Payload format version, for future web-side migrations.
    let version: Int
    /// Always "roomplan".
    let source: String
    /// ISO-8601 timestamp of when the scan finished processing.
    let scannedAt: String
    /// Tallest wall height in the room. RoomPlan detects no ceiling
    /// surface, so for the flat ceilings this estimator prices,
    /// wall height IS the ceiling height.
    let ceilingHeightFt: Double
    let ceilingHeight: FeetInches
    let walls: [ScanWall]
    let windows: [ScanOpening]
    let doors: [ScanOpening]
    /// Cased openings (no door slab) — counted separately so the web
    /// side never mistakes one for a door deduction.
    let openings: [ScanOpening]
}

/// Error shape delivered through window.handleScanError(...).
struct ScanErrorMessage: Codable {
    /// "cancelled" | "camera-denied" | "lidar-unsupported" |
    /// "scan-failed" | "encode-failed"
    let code: String
    let message: String
}
