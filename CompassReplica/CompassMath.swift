import Foundation
import CoreGraphics
import Contacts

func localized(_ key: String, bundle: Bundle = .main) -> String { NSLocalizedString(key, bundle: bundle, comment: "") }

func normalizedHeading(_ degrees: Double) -> Double {
    (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
}

func directionName(_ degrees: Double, bundle: Bundle = .main) -> String {
    localized(["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((normalizedHeading(degrees) + 22.5) / 45) % 8], bundle: bundle)
}

func coordinateText(_ value: Double, latitude: Bool, bundle: Bundle = .main) -> String {
    let total = Int((abs(value) * 36000).rounded())
    let hemisphere = localized(latitude ? (value < 0 ? "latitude.south" : "latitude.north") : (value < 0 ? "longitude.west" : "longitude.east"), bundle: bundle)
    return String(format: localized("%2$d°%3$d′%4$@″ %1$@", bundle: bundle), hemisphere, total / 36000, total / 600 % 60, String(format: "%.1f", Double(total % 600) / 10))
}

func elevationText(_ meters: Double) -> String {
    let formatter = MeasurementFormatter()
    formatter.locale = .current
    formatter.unitOptions = .providedUnit
    formatter.unitStyle = .short
    formatter.numberFormatter.maximumFractionDigits = 1
    formatter.numberFormatter.minimumFractionDigits = 1
    return String(format: localized("Elevation %@"), formatter.string(from: Measurement(value: meters, unit: UnitLength.meters)))
}

func streetAddressText(_ address: CNPostalAddress?) -> String? {
    guard let address, !address.street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct LevelDetector {
    // Separate thresholds prevent repeated feedback from sensor noise near level.
    var enterDegrees = 1.0
    var exitDegrees = 2.0
    private var wasLevel: Bool?

    mutating func update(degrees: Double) -> Bool {
        guard degrees.isFinite, degrees >= 0 else { wasLevel = nil; return false }
        let level = degrees <= (wasLevel == true ? exitDegrees : enterDegrees)
        let reachedLevel = wasLevel == false && level
        wasLevel = level
        return reachedLevel
    }
}

func limitedOffset(_ offset: CGSize, radius: Double) -> CGSize {
    let distance = hypot(offset.width, offset.height)
    guard distance > 0 else { return .zero }
    let factor = min(1, max(0, radius) / distance)
    return CGSize(width: offset.width * factor, height: offset.height * factor)
}

// Twenty-four mountains, clockwise from north (子), 15° per sector.
let compassMountains = Array("子癸丑艮寅甲卯乙辰巽巳丙午丁未坤申庚酉辛戌乾亥壬").map(String.init)

func mountainName(_ heading: Double) -> String {
    compassMountains[Int((normalizedHeading(heading) + 7.5) / 15) % 24]
}

let compassTrigrams = ["☵坎", "☶艮", "☳震", "☴巽", "☲離", "☷坤", "☱兌", "☰乾"]

func compassExplanation(_ heading: Double, bundle: Bundle = .main) -> String {
    let sector = Int((normalizedHeading(heading) + 7.5) / 15) % 24
    let trigram = String(compassTrigrams[Int((normalizedHeading(heading) + 22.5) / 45) % 8].suffix(1))
    let range = String(format: "%.1f°–%.1f°", normalizedHeading(Double(sector) * 15 - 7.5), normalizedHeading(Double(sector) * 15 + 7.5))
    let facing = String(format: localized("Facing %@ · Sitting %@", bundle: bundle), mountainName(heading), mountainName(heading + 180))
    let detail = String(format: localized("%@ trigram · %@ · %@", bundle: bundle), trigram, directionName(heading, bundle: bundle), range)
    return facing + "\n" + detail
}

func levelAngles(x: Double, y: Double, z: Double) -> CGSize {
    CGSize(width: atan2(x, hypot(y, z)) * 180 / .pi,
           height: atan2(-y, hypot(x, z)) * 180 / .pi)
}

func levelMostlyAligned(offset: CGSize, radius: Double) -> Bool {
    // Equal circles overlap by just over half their area at 0.8 radii apart.
    radius > 0 && hypot(offset.width, offset.height) <= radius * 0.8
}

// Keep the dial and its readings inside the usable height when the window unfolds.
func compassContentWidth(availableWidth: Double, availableHeight: Double) -> Double {
    max(0, min(availableWidth, availableHeight / 1.78))
}
