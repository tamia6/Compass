import SwiftUI
import CoreLocation
import CoreMotion

@main
struct CompassApp: App {
    @UIApplicationDelegateAdaptor(CompassOrientationDelegate.self) private var orientationDelegate
    var body: some Scene { WindowGroup { CompassView() } }
}

final class CompassOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if #available(iOS 27.1, *) { return .all }
        return .portrait
    }
}

@Observable
final class CompassSensors: NSObject, CLLocationManagerDelegate {
    var heading: Double?
    var location: CLLocation?
    var city = localized("Locating…")
    var tilt = CGSize.zero
    var levelDegrees: Double?
    var angles = CGSize.zero
    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    @ObservationIgnored private weak var referenceView: UIView?
    private var levelDetector = LevelDetector()
    private let levelFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private let geocoder = CLGeocoder()
    private var lastGeocode = Date.distantPast
    private var active = false
    let demo = ProcessInfo.processInfo.arguments.contains("--preview")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        if demo {
            levelDegrees = 0
            heading = 278
            city = localized("Sample address")
            // Preview fixture only; never presented as a live measurement.
            location = CLLocation(coordinate: .init(latitude: 30.657, longitude: 104.066), altitude: 500, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        }
    }

    @available(iOS 27.0, *)
    func referenceSensors(to view: UIView) {
        guard referenceView !== view else { return }
        referenceView = view
        levelDetector = LevelDetector()
        // Tie measurements to the visible display, including its orientation and fold pose.
        manager.headingBody = view
        motion.deviceMotionBody = view
    }

    func start() {
        guard !demo, !active else { return }
        active = true
        levelFeedback.prepare()
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { locationManagerDidChangeAuthorization(manager) }
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1 / 30
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, self.active, let gravity = data?.gravity else { return }
                self.angles = levelAngles(x: gravity.x, y: gravity.y, z: gravity.z)
                self.tilt = CGSize(width: gravity.x * 28, height: -gravity.y * 28)
                let degrees = atan2(hypot(gravity.x, gravity.y), abs(gravity.z)) * 180 / .pi
                self.levelDegrees = degrees
                if self.levelDetector.update(degrees: degrees) {
                    self.levelFeedback.impactOccurred(intensity: 1)
                    self.levelFeedback.prepare()
                }
            }
        }
    }

    func stop() {
        active = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
        levelDetector = LevelDetector()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard active else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted:
            location = nil
            city = localized("Allow location in Settings")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { heading = nil; return }
        heading = normalizedHeading(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = latest
        guard Date().timeIntervalSince(lastGeocode) > 60, !geocoder.isGeocoding else { return }
        lastGeocode = Date()
        geocoder.reverseGeocodeLocation(latest, preferredLocale: .current) { [weak self] places, _ in
            guard let self else { return }
            guard self.manager.authorizationStatus == .authorizedWhenInUse || self.manager.authorizationStatus == .authorizedAlways else { return }
            if let place = places?.first {
                let province = place.administrativeArea ?? ""
                let locality = place.locality ?? place.subAdministrativeArea ?? ""
                self.city = province == locality || province.isEmpty ? locality : (locality.isEmpty ? province : String(format: localized("%@, %@"), locality, province))
                if let district = place.subLocality, !district.isEmpty, district != locality {
                    self.city = self.city.isEmpty ? district : String(format: localized("%@, %@"), district, self.city)
                }
                self.city = streetAddressText(place.postalAddress) ?? self.city
                if self.city.isEmpty { self.city = localized("Current Location") }
            } else { self.city = localized("Current Location") }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        location = nil
        city = manager.authorizationStatus == .denied ? localized("Allow location in Settings") : localized("Location unavailable")
    }
}

struct CompassView: View {
    @AppStorage("displayMode") private var mode = 0
    private var fengShui: Bool { mode == 1 }
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var sensors = CompassSensors()
    @State private var levelExpanded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if #available(iOS 27.1, *) {
                AdaptiveCompassView(sensors: sensors, mode: $mode, appearance: $appearance, levelExpanded: $levelExpanded)
            } else {
                legacyContent
            }
        }
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
        .onAppear {
            if UserDefaults.standard.object(forKey: "displayMode") == nil {
                mode = UserDefaults.standard.bool(forKey: "fengShuiMode") ? 1 : 0
            }
            sensors.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sensors.start() } else { sensors.stop() }
        }
    }
    private var legacyContent: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - geometry.safeAreaInsets.leading - geometry.safeAreaInsets.trailing)
            let centerX = geometry.safeAreaInsets.leading + availableWidth / 2
            let contentTop = max(geometry.safeAreaInsets.top + 24, 78) + 38
            let contentHeight = max(0, geometry.size.height - contentTop - max(geometry.safeAreaInsets.bottom, 20))
            let width = compassContentWidth(availableWidth: availableWidth, availableHeight: contentHeight)
            ZStack {
                Color(uiColor: .systemBackground)
                Group {
                if mode == 2 {
                    LevelView(degrees: sensors.levelDegrees, angles: sensors.angles, tilt: sensors.tilt, width: width)
                } else {
                VStack(spacing: width * (44.0 / 278.0)) {
                    CompassDial(levelExpanded: $levelExpanded, heading: sensors.heading ?? 0, tilt: sensors.tilt, fengShui: fengShui)
                        .frame(width: width, height: width * (238.0 / 278.0))
                    VStack(spacing: width * 0.022) {
                        Text(sensors.heading.map { "\(Int(normalizedHeading($0.rounded())))° \(fengShui ? mountainName($0) : directionName($0))" } ?? "—°")
                            .font(.system(size: width * 0.173, weight: .thin))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityLabel(sensors.heading.map { String(format: localized(fengShui ? "%d degrees, facing %@" : "%d degrees, %@"), Int(normalizedHeading($0.rounded())), fengShui ? mountainName($0) : directionName($0)) } ?? localized("Heading unavailable"))
                        if fengShui, let heading = sensors.heading {
                            Text(compassExplanation(heading))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !fengShui {
                            Text(sensors.city)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                            VStack(spacing: 8) {
                                Text(sensors.location.map { coordinateText($0.coordinate.latitude, latitude: true) + "  " + coordinateText($0.coordinate.longitude, latitude: false) } ?? localized("Coordinates —"))
                                Text(sensors.location.flatMap { $0.verticalAccuracy >= 0 ? elevationText($0.altitude) : nil } ?? localized("Elevation —"))
                            }
                            .monospacedDigit()
                            .padding(.top, 3)
                        }
                    }
                    .font(.system(size: width * 0.045))
                    .foregroundStyle(.primary)
                    .frame(width: width * 0.94)
                    .fixedSize(horizontal: false, vertical: true)
                }
                }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, height: contentHeight, alignment: .center)
                .position(x: centerX, y: contentTop + contentHeight / 2)
                Button {
                    appearance = colorScheme == .dark ? "light" : "dark"
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode"))
                .accessibilityHint(Text("Long press to follow system"))
                .contextMenu {
                    Button("Follow system", systemImage: "circle.lefthalf.filled") { appearance = "system" }
                    Link("Privacy policy", destination: URL(string: "https://compass-level-support.pages.dev/privacy")!)
                    Link("Support", destination: URL(string: "https://compass-level-support.pages.dev/support")!)
                }
                .position(x: geometry.safeAreaInsets.leading + 38, y: max(geometry.safeAreaInsets.top + 24, 78))
                Button {
                    mode = (mode + 1) % 3
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(mode == 2 ? Color.green : (fengShui ? Color.red : Color.primary))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode == 2 ? "Switch to standard compass" : (fengShui ? "Switch to level" : "Switch to Feng Shui compass")))
                .accessibilityValue(Text(mode == 2 ? "Level" : (fengShui ? "Feng Shui compass" : "Standard compass")))
                .position(x: geometry.size.width - geometry.safeAreaInsets.trailing - 38, y: max(geometry.safeAreaInsets.top + 24, 78))
                if sensors.demo {
                    Text("Preview · Sample data").font(.caption2).foregroundStyle(.gray)
                        .position(x: centerX, y: geometry.size.height * 0.95)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }


}

struct LevelView: View {
    let degrees: Double?
    let angles: CGSize
    let tilt: CGSize
    let width: Double

    var body: some View {
        VStack(spacing: width * 0.08) {
            Text("Level").font(.system(size: width * 0.06, weight: .medium))
            LevelDial(degrees: degrees, tilt: tilt, diameter: width * 0.84)
            Text(degrees.map { String(format: "%.1f°", $0) } ?? "—°")
                .font(.system(size: width * 0.173, weight: .thin))
                .foregroundStyle(degrees.map { $0 <= 1 } == true ? Color.green : .primary)
            LevelReadings(degrees: degrees, angles: angles)
                .font(.system(size: width * 0.045))
        }
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .frame(width: width * 0.94)
    }
}

struct CompassDial: View {
    @Binding var levelExpanded: Bool
    let heading: Double
    let tilt: CGSize
    var fengShui = false

    var body: some View {
        Canvas { context, size in
            // Measured in the mirrored screen's 278-point-wide reference image.
            // Scale the entire drawing once so every detail keeps the original proportions.
            let scale = size.width / 278
            context.scaleBy(x: scale, y: scale)
            let center = CGPoint(x: 139, y: size.height / scale / 2)
            let radius = 88.5
            func point(_ degrees: Double, _ distance: Double) -> CGPoint {
                let angle = (degrees - heading - 90) * .pi / 180
                return CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            }
            func line(_ a: CGPoint, _ b: CGPoint, color: Color, width: Double) {
                var path = Path(); path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .color(color), lineWidth: width)
            }
            for degree in stride(from: 0, to: 360, by: 2) {
                let major = degree % 30 == 0
                line(point(Double(degree), radius - (major ? 13 : 11)), point(Double(degree), radius), color: .primary.opacity(major ? 1 : 0.65), width: major ? 1 : 0.55)
            }
            for degree in stride(from: 0, to: 360, by: 30) {
                context.draw(Text("\(degree)").font(.system(size: 9)).foregroundStyle(.primary.opacity(0.8)), at: point(Double(degree), 111))
            }
            if fengShui {
                for ring in [32.0, 55.0, 75.0] {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)), with: .color(.primary.opacity(0.5)), lineWidth: 0.6)
                }
                for (index, mountain) in compassMountains.enumerated() {
                    let degrees = Double(index) * 15
                    line(point(degrees - 7.5, 55), point(degrees - 7.5, 75), color: .primary.opacity(0.35), width: 0.5)
                    context.draw(Text(mountain).font(.system(size: 10, weight: .medium)).foregroundStyle(mountain == mountainName(heading) ? Color.red : Color.primary), at: point(degrees, 65))
                }
                // Later-Heaven arrangement: 坎 north, 離 south, 震 east, 兌 west.
                for (index, trigram) in compassTrigrams.enumerated() {
                    let degrees = Double(index) * 45
                    line(point(degrees - 22.5, 32), point(degrees - 22.5, 55), color: .primary.opacity(0.35), width: 0.5)
                    context.draw(Text(trigram).font(.system(size: 9, weight: .medium)).foregroundStyle(.primary), at: point(degrees, 43))
                }
            } else {
                for degree in [0.0, 90.0, 180.0, 270.0] {
                    context.draw(Text(directionName(degree)).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary), at: point(degree, 62))
                }
            }
            var north = Path()
            north.move(to: point(0, 100))
            north.addLine(to: point(-2.5, 92))
            north.addLine(to: point(2.5, 92))
            north.closeSubpath()
            context.fill(north, with: .color(.red))
            line(CGPoint(x: center.x, y: center.y - radius - 30), CGPoint(x: center.x, y: center.y - radius + 11), color: .primary, width: 1.5)
            if levelExpanded {
                context.fill(Path(ellipseIn: CGRect(x: center.x - 76, y: center.y - 76, width: 152, height: 152)), with: .color(Color(uiColor: .systemBackground)))
                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: 2.5, y: 2.5)
                context.translateBy(x: -center.x, y: -center.y)
            }
            let reach = levelExpanded || fengShui ? 28.0 : 42.0
            line(CGPoint(x: center.x - reach, y: center.y), CGPoint(x: center.x + reach, y: center.y), color: .primary.opacity(0.22), width: 1)
            line(CGPoint(x: center.x, y: center.y - reach), CGPoint(x: center.x, y: center.y + reach), color: .primary.opacity(0.22), width: 1)
        }
        .accessibilityHidden(true)
        .onChange(of: fengShui) { _, _ in levelExpanded = false }
        .overlay {
            GeometryReader { geometry in
                let scale = geometry.size.width / 278
                let zoom = levelExpanded ? 2.5 : 1.0
                let diameter = 49 * scale * zoom
                // Keep the level indicator inside the inner ring.
                let offset = limitedOffset(CGSize(width: tilt.width * zoom, height: tilt.height * zoom), radius: ((fengShui && !levelExpanded ? 31.0 : 74.0) - 24.5 * zoom) * scale)
                ZStack {
                    Circle().fill(.primary.opacity(0.13))
                    Rectangle().fill(.primary.opacity(0.65)).frame(width: 10 * scale * zoom, height: scale)
                    Rectangle().fill(.primary.opacity(0.65)).frame(width: scale, height: 10 * scale * zoom)
                }
                .frame(width: diameter, height: diameter)
                .offset(offset)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                Button {
                    levelExpanded.toggle()
                } label: {
                    Circle().fill(.clear).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: max(44, geometry.size.width * (levelExpanded ? 0.55 : 0.22)), height: max(44, geometry.size.width * (levelExpanded ? 0.55 : 0.22)))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .accessibilityLabel(Text(levelExpanded ? "Reduce level" : "Enlarge level"))
            }
        }
    }
}

#Preview { CompassView() }

@available(iOS 27.1, *)
private struct AdaptiveCompassView: View {
    let sensors: CompassSensors
    @Binding var mode: Int
    @Binding var appearance: String
    @Binding var levelExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let sideBySide = geometry.size.width > geometry.size.height
                let folded = geometry.reservedRegions(kind: .division).contains { $0.isActive }
                Group {
                    if folded {
                        ArrangementView {
                            instrumentPane
                        } secondary: {
                            readingsPane
                        }
                        .arrangementViewStyle(.split)
                    } else {
                        let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                        layout {
                            instrumentPane
                            readingsPane
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appearance = colorScheme == .dark ? "light" : "dark"
                    } label: {
                        Label(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode", systemImage: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                    }
                    .contextMenu {
                        Button("Follow system", systemImage: "circle.lefthalf.filled") { appearance = "system" }
                        Link("Privacy policy", destination: URL(string: "https://compass-level-support.pages.dev/privacy")!)
                        Link("Support", destination: URL(string: "https://compass-level-support.pages.dev/support")!)
                    }
                    .accessibilityHint(Text("Long press to follow system"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mode = (mode + 1) % 3 } label: {
                        Label(mode == 2 ? "Switch to standard compass" : (mode == 1 ? "Switch to level" : "Switch to Feng Shui compass"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(mode == 2 ? .green : (mode == 1 ? .red : .primary))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var instrumentPane: some View {
        GeometryReader { pane in
            let aspect = mode == 2 ? 1.0 : 238.0 / 278.0
            let width = max(0, min(pane.size.width, pane.size.height / aspect))
            Group {
                if mode == 2 {
                    LevelDial(degrees: sensors.levelDegrees, tilt: sensors.tilt, diameter: width * 0.94)
                } else {
                    CompassDial(levelExpanded: $levelExpanded, heading: sensors.heading ?? 0, tilt: sensors.tilt, fengShui: mode == 1)
                        .frame(width: width, height: width * (238.0 / 278.0))
                }
            }
            .background(SensorReference(sensors: sensors).allowsHitTesting(false))
            .frame(width: pane.size.width, height: pane.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readingsPane: some View {
        GeometryReader { pane in
            ScrollView {
                VStack(spacing: 12) {
                    if mode == 2 {
                        Text("Level").font(.title2)
                        Text(sensors.levelDegrees.map { String(format: "%.1f°", $0) } ?? "—°")
                            .font(.system(size: 64, weight: .thin)).foregroundStyle(sensors.levelDegrees.map { $0 <= 1 } == true ? Color.green : .primary)
                        LevelReadings(degrees: sensors.levelDegrees, angles: sensors.angles)
                    } else {
                        Text(sensors.heading.map { "\(Int(normalizedHeading($0.rounded())))° \(mode == 1 ? mountainName($0) : directionName($0))" } ?? "—°")
                            .font(.system(size: 64, weight: .thin))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityLabel(sensors.heading.map { String(format: localized(mode == 1 ? "%d degrees, facing %@" : "%d degrees, %@"), Int(normalizedHeading($0.rounded())), mode == 1 ? mountainName($0) : directionName($0)) } ?? localized("Heading unavailable"))
                        if mode == 1, let heading = sensors.heading {
                            Text(compassExplanation(heading))
                        } else if mode == 0 {
                            Text(sensors.city.replacingOccurrences(of: "\n", with: " "))
                            Text(sensors.location.map { coordinateText($0.coordinate.latitude, latitude: true) + "\n" + coordinateText($0.coordinate.longitude, latitude: false) } ?? localized("Coordinates —"))
                            Text(sensors.location.flatMap { $0.verticalAccuracy >= 0 ? elevationText($0.altitude) : nil } ?? localized("Elevation —"))
                        }
                    }
                    if sensors.demo { Text("Preview · Sample data").font(.caption).foregroundStyle(.secondary) }
                }
                .font(.title3)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: pane.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@available(iOS 27.0, *)
private struct SensorReference: UIViewRepresentable {
    let sensors: CompassSensors
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        sensors.referenceSensors(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        sensors.referenceSensors(to: uiView)
    }
}

private struct LevelDial: View {
    let degrees: Double?
    let tilt: CGSize
    let diameter: Double
    var body: some View {
        let isLevel = degrees.map { $0 <= 1 } ?? false
        let offset = limitedOffset(CGSize(width: tilt.width / 28 * diameter, height: tilt.height / 28 * diameter), radius: diameter * 0.29)
        let referenceColor: Color = isLevel ? .green : (degrees != nil && levelMostlyAligned(offset: offset, radius: diameter * 0.2) ? .yellow : .primary.opacity(0.25))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1)
            Rectangle().fill(referenceColor).frame(height: 1)
            Rectangle().fill(referenceColor).frame(width: 1)
            Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1).frame(width: diameter * 0.4, height: diameter * 0.4)
            if degrees != nil {
                Circle().fill(isLevel ? Color.green.opacity(0.5) : Color.primary.opacity(0.18))
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
                    .overlay {
                        ZStack {
                            Rectangle().frame(width: diameter * 0.22, height: 1.5)
                            Rectangle().frame(width: 1.5, height: diameter * 0.22)
                        }.foregroundStyle(Color.primary.opacity(0.75))
                    }
                    .offset(offset)
            }
        }
        .frame(width: diameter, height: diameter).accessibilityHidden(true)
    }
}

private struct LevelReadings: View {
    let degrees: Double?
    let angles: CGSize
    var body: some View {
        VStack(spacing: 16) {
            Text(degrees == nil ? "Motion unavailable" : (degrees.map { $0 <= 1 } == true ? "Level reached" : "Tilt"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { horizontal; vertical }
                VStack(spacing: 16) { horizontal; vertical }
            }
        }
    }
    private var horizontal: some View {
        VStack(spacing: 6) { Text("Horizontal tilt"); Text(degrees == nil ? "—°" : String(format: "%.1f°", angles.width)) }
    }
    private var vertical: some View {
        VStack(spacing: 6) { Text("Vertical tilt"); Text(degrees == nil ? "—°" : String(format: "%.1f°", angles.height)) }
    }
}
