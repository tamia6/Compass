import Foundation
import CoreGraphics
import Contacts
assert(coordinateText(30.657, latitude: true) != coordinateText(30.65703, latitude: true))
assert(elevationText(500.1) != elevationText(500.2))
assert(normalizedHeading(-1) == 359)
assert(normalizedHeading(360) == 0)
assert(directionName(278) == "W")
assert(directionName(359) == "N")
assert(directionName(22.5) == "NE")
// Pass the built .app directory to verify the actual compiled localization resources.
if CommandLine.arguments.count > 1 {
    let app = CommandLine.arguments[1]
    for (language, west) in [("en", "W"), ("zh-Hans", "西"), ("zh-Hant", "西"), ("ja", "西"), ("ko", "서"), ("fr", "O"), ("de", "W"), ("es", "O")] {
        let bundle = Bundle(path: app + "/" + language + ".lproj")!
        assert(directionName(278, bundle: bundle) == west, language)
        assert(!localized("latitude.north", bundle: bundle).contains("latitude."), language)
        assert(!coordinateText(12.999999, latitude: true, bundle: bundle).contains("60"), language)
    }
    let supported = Bundle(path: app)!.localizations
    for (preferred, expected) in [("en-US", "en"), ("zh-Hans-CN", "zh-Hans"), ("zh-Hant-TW", "zh-Hant")] {
        assert(Bundle.preferredLocalizations(from: supported, forPreferences: [preferred]).first == expected)
    }
    for language in ["en", "zh-Hans", "zh-Hant"] {
        let bundle = Bundle(path: app + "/" + language + ".lproj")!
        assert(localized("Level", bundle: bundle) == (language == "en" ? "Level" : (language == "zh-Hans" ? "水平仪" : "水平儀")))
        assert(bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist") == (language == "en" ? "Compass & Level" : (language == "zh-Hans" ? "指南针与水平仪" : "指南針與水平儀")))
    }
    let zh = Bundle(path: app + "/zh-Hans.lproj")!
    let en = Bundle(path: app + "/en.lproj")!
    assert(coordinateText(12.999999, latitude: true, bundle: zh) == "北纬13°0′0.0″")
    assert(coordinateText(-104.066, latitude: false, bundle: zh) == "西经104°3′57.6″")
    assert(coordinateText(-104.066, latitude: false, bundle: en) == "104°3′57.6″ W")
}
let address = CNMutablePostalAddress()
assert(streetAddressText(nil) == nil)
assert(streetAddressText(address) == nil)
address.street = "   "
assert(streetAddressText(address) == nil)
address.street = "123 Main Street"
address.city = "Springfield"
address.isoCountryCode = "US"
assert(streetAddressText(address)!.contains("123 Main Street"))
assert(streetAddressText(address)!.contains("Springfield"))
address.street = "人民南路一段1号"
address.city = "成都市"
address.isoCountryCode = "CN"
assert(streetAddressText(address)!.contains("人民南路一段1号"))
var level = LevelDetector()
assert(!level.update(degrees: 0.5)) // No vibration just from opening a level phone.
assert(!level.update(degrees: 1.5))
assert(!level.update(degrees: 3))
assert(level.update(degrees: 1))
for degrees in [0.2, 1.1, 0.9, 1.9, 2.0] { assert(!level.update(degrees: degrees)) }
assert(!level.update(degrees: 2.1))
assert(level.update(degrees: 0.5))
assert(!level.update(degrees: .nan))
assert(!level.update(degrees: 0))
assert(limitedOffset(.zero, radius: 10) == .zero)
assert(limitedOffset(CGSize(width: 3, height: 4), radius: 10) == CGSize(width: 3, height: 4))
let bounded = limitedOffset(CGSize(width: 30, height: 40), radius: 10)
assert(abs(hypot(bounded.width, bounded.height) - 10) < 0.0001)
assert(bounded == CGSize(width: 6, height: 8))
assert(limitedOffset(CGSize(width: 10, height: 10), radius: -1) == .zero)
assert(compassMountains.count == 24 && Set(compassMountains).count == 24)
assert(mountainName(0) == "子" && mountainName(359) == "子")
assert(mountainName(90) == "卯" && mountainName(180) == "午" && mountainName(270) == "酉")
assert(mountainName(7.49) == "子" && mountainName(7.5) == "癸")
assert(mountainName(-15) == "壬" && mountainName(360) == "子")
assert(compassExplanation(278).contains("Facing 辛 · Sitting 乙"))
assert(compassExplanation(278).contains("兌 trigram · W · 277.5°–292.5°"))
assert(compassExplanation(0).contains("352.5°–7.5°"))
assert(compassExplanation(278).split(separator: "\n").count == 2)
print("Compass checks passed")

assert(levelAngles(x: 0, y: 0, z: -1) == .zero)
assert(levelAngles(x: 0, y: 0, z: 1) == .zero)
assert(abs(levelAngles(x: 1, y: 0, z: 1).width - 45) < 0.001)
assert(abs(levelAngles(x: 0, y: 1, z: 0).height + 90) < 0.001)

assert(levelMostlyAligned(offset: .zero, radius: 20))
assert(levelMostlyAligned(offset: CGSize(width: 16, height: 0), radius: 20))
assert(!levelMostlyAligned(offset: CGSize(width: 16.1, height: 0), radius: 20))
assert(!levelMostlyAligned(offset: CGSize(width: 12, height: 12), radius: 20))
assert(!levelMostlyAligned(offset: .zero, radius: 0))

// Resizing must fit both constraints and preserve the original tall-phone size.
assert(compassContentWidth(availableWidth: 402, availableHeight: 738) == 402)
for size in [CGSize(width: 700, height: 650), CGSize(width: 900, height: 400), CGSize(width: 320, height: 600)] {
    let width = compassContentWidth(availableWidth: size.width, availableHeight: size.height)
    assert(width <= size.width && width * 1.78 <= size.height + 0.001)
}
assert(compassContentWidth(availableWidth: 400, availableHeight: 0) == 0)
