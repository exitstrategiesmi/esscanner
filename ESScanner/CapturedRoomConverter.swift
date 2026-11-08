//  CapturedRoomConverter.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  Converts Apple's CapturedRoom into the estimator's ScanPayload.
//  RoomPlan reports dimensions in meters as simd_float3 where, for a
//  wall or opening surface, x = width/length along the surface and
//  y = height. The estimator works in feet, so everything is
//  converted here, once, on the native side.

import Foundation
import RoomPlan

enum CapturedRoomConverter {

    private static let metersToFeet = 3.28084

    /// Meters -> decimal feet, rounded to 2 places.
    private static func feet(_ meters: Float) -> Double {
        let value = Double(meters) * metersToFeet
        return (value * 100).rounded() / 100
    }

    /// RoomPlan confidence as a plain string ("low"/"medium"/"high").
    /// String(describing:) on the enum yields the case name without
    /// depending on any raw-value representation.
    private static func confidence(of surface: CapturedRoom.Surface) -> String {
        String(describing: surface.confidence)
    }

    static func payload(from room: CapturedRoom, date: Date = Date()) -> ScanPayload {
        // Map each wall's identifier to its position so openings can
        // point back at the wall that hosts them (RoomPlan links a
        // door/window/opening to its wall via parentIdentifier).
        let wallIndexByID: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: room.walls.enumerated().map { ($0.element.identifier, $0.offset) }
        )

        func opening(_ surface: CapturedRoom.Surface, kind: String) -> ScanOpening {
            let width = feet(surface.dimensions.x)
            let height = feet(surface.dimensions.y)
            return ScanOpening(
                kind: kind,
                widthFt: width,
                heightFt: height,
                width: FeetInches(decimalFeet: width),
                height: FeetInches(decimalFeet: height),
                confidence: confidence(of: surface),
                wallIndex: surface.parentIdentifier.flatMap { wallIndexByID[$0] }
            )
        }

        let doors = room.doors.map { opening($0, kind: "door") }
        let windows = room.windows.map { opening($0, kind: "window") }
        let openings = room.openings.map { opening($0, kind: "opening") }
        let allOpenings = doors + windows + openings

        let walls: [ScanWall] = room.walls.enumerated().map { index, surface in
            let length = feet(surface.dimensions.x)
            let height = feet(surface.dimensions.y)
            return ScanWall(
                index: index,
                lengthFt: length,
                heightFt: height,
                length: FeetInches(decimalFeet: length),
                height: FeetInches(decimalFeet: height),
                confidence: confidence(of: surface),
                openings: allOpenings.filter { $0.wallIndex == index }
            )
        }

        // No ceiling surface exists in RoomPlan; the tallest wall is
        // the ceiling height for the flat ceilings being estimated.
        let ceilingHeightFt = room.walls.map { feet($0.dimensions.y) }.max() ?? 0

        return ScanPayload(
            version: 1,
            source: "roomplan",
            scannedAt: ISO8601DateFormatter().string(from: date),
            ceilingHeightFt: ceilingHeightFt,
            ceilingHeight: FeetInches(decimalFeet: ceilingHeightFt),
            walls: walls,
            windows: windows,
            doors: doors,
            openings: openings
        )
    }
}
