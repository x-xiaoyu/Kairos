import CoreLocation
import Foundation

enum UserContextMode: String, CaseIterable, Identifiable {
    case auto
    case home
    case away

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .auto: "自动跟随定位"
        case .home: "在家"
        case .away: "外出"
        }
    }

    var menuSymbol: String {
        switch self {
        case .auto: "sparkles"
        case .home: "house.fill"
        case .away: "location.fill"
        }
    }
}

enum PlacePresence: Equatable {
    case unknown
    case atHome
    case away

    var headline: String {
        switch self {
        case .unknown: "还不知道你在哪"
        case .atHome: "你现在在家"
        case .away: "你现在出门在外"
        }
    }
}

struct HomeLocation: Equatable {
    var latitude: Double
    var longitude: Double
    var address: String

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    static var stored: HomeLocation? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: Keys.set) else { return nil }
            return HomeLocation(
                latitude: defaults.double(forKey: Keys.latitude),
                longitude: defaults.double(forKey: Keys.longitude),
                address: defaults.string(forKey: Keys.address) ?? "家"
            )
        }
        set {
            let defaults = UserDefaults.standard
            if let value = newValue {
                defaults.set(true, forKey: Keys.set)
                defaults.set(value.latitude, forKey: Keys.latitude)
                defaults.set(value.longitude, forKey: Keys.longitude)
                defaults.set(value.address, forKey: Keys.address)
            } else {
                defaults.set(false, forKey: Keys.set)
                defaults.removeObject(forKey: Keys.latitude)
                defaults.removeObject(forKey: Keys.longitude)
                defaults.removeObject(forKey: Keys.address)
            }
        }
    }

    private enum Keys {
        static let set = "hasHomeLocation"
        static let latitude = "homeLatitude"
        static let longitude = "homeLongitude"
        static let address = "homeAddress"
    }
}

enum PlaceContext {
    static let homeRadius: CLLocationDistance = 180

    static func presence(current: CLLocation?, home: HomeLocation?) -> PlacePresence {
        guard let current, let home else { return .unknown }
        return current.distance(from: home.location) <= homeRadius ? .atHome : .away
    }

    static func resolvedPresence(mode: UserContextMode, current: CLLocation?, home: HomeLocation?) -> PlacePresence {
        switch mode {
        case .home: .atHome
        case .away: .away
        case .auto: presence(current: current, home: home)
        }
    }

    static func isDoableNow(_ place: TaskPlace, presence: PlacePresence) -> Bool {
        switch presence {
        case .unknown: true
        case .atHome: place != .outing
        case .away: place != .home
        }
    }

    static func isPinnedByUrgency(_ risk: RiskLevel) -> Bool {
        risk == .high || risk == .critical
    }

    static func shouldHighlightNow(_ item: PlannedTask, presence: PlacePresence) -> Bool {
        isPinnedByUrgency(item.risk) || isDoableNow(item.task.place, presence: presence)
    }

    static func deferredCaption(for place: TaskPlace, presence: PlacePresence) -> String? {
        guard !isDoableNow(place, presence: presence) else { return nil }
        switch presence {
        case .atHome: return "出门再做"
        case .away: return "回家再做"
        case .unknown: return nil
        }
    }

    static func availabilityNote(for item: PlannedTask, presence: PlacePresence) -> String {
        if isPinnedByUrgency(item.risk), !isDoableNow(item.task.place, presence: presence) {
            return presence == .atHome ? "虽然要出门，但已经很紧迫" : "虽然通常在家做，但已经很紧迫"
        }
        return deferredCaption(for: item.task.place, presence: presence) ?? item.task.place.displayName
    }

    static func suggestedStart(in plan: [PlannedTask], presence: PlacePresence) -> PlannedTask? {
        if let urgent = plan.first(where: { isPinnedByUrgency($0.risk) }) {
            return urgent
        }
        let doable = plan.filter { isDoableNow($0.task.place, presence: presence) }
        guard presence == .atHome else { return doable.first ?? plan.first }
        let bestLoad = doable.map(\.task.cognitiveLoad).max(by: { loadRank($0) < loadRank($1) })
        if let bestLoad, let preferred = doable.first(where: { $0.task.cognitiveLoad == bestLoad }) {
            return preferred
        }
        return doable.first ?? plan.first
    }

    static func laterSectionTitle(presence: PlacePresence) -> String {
        switch presence {
        case .atHome: "出门再做"
        case .away: "回家再做"
        case .unknown: "稍后再做"
        }
    }

    private static func loadRank(_ load: CognitiveLoad) -> Int {
        switch load {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

enum TaskContextGuess {
    static func place(from title: String) -> TaskPlace {
        let text = title.lowercased()
        if matches(text, ["采购", "买菜", "超市", "商场", "逛街", "寄件", "邮局", "银行", "取号", "加油站", "药店", "门诊", "外卖柜以外", "出门", "外出", "跑步", "健身房外"]) {
            return .outing
        }
        if matches(text, ["洗衣", "洗衣服", "洗碗", "打扫", "扫地", "拖地", "做饭", "煮饭", "家务", "整理房间", "倒垃圾", "在家", "沙发"]) {
            return .home
        }
        return .anywhere
    }

    static func cognitiveLoad(from title: String) -> CognitiveLoad {
        let text = title.lowercased()
        if matches(text, ["论文", "报告", "设计", "面试", "算法", "leetcode", "复习", "文档", "方案", "写作", "代码", "编程", "研究", "周报"]) {
            return .high
        }
        if matches(text, ["洗衣", "洗碗", "打扫", "采购", "买菜", "倒垃圾", "散步", "跑步", "收拾"]) {
            return .low
        }
        return .medium
    }

    private static func matches(_ text: String, _ keys: [String]) -> Bool {
        keys.contains { text.contains($0) }
    }
}

@MainActor
final class HomeLocationPicker: NSObject, ObservableObject {
    @Published var isSaving = false
    @Published var message: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func captureCurrentAsHome() {
        Task { await saveCurrent() }
    }

    func clear() {
        HomeLocation.stored = nil
        message = "已清除家庭地址。"
    }

    private func saveCurrent() async {
        isSaving = true
        message = nil
        defer { isSaving = false }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            message = "请允许定位后，再点一次“把当前位置设为家”。"
            return
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            message = "定位未开启。可在 iPhone 设置里允许 Kairos 使用位置。"
            return
        }
        do {
            let location = try await requestLocation()
            var address = "家"
            if let place = try? await CLGeocoder().reverseGeocodeLocation(location), let first = place.first {
                address = [first.name, first.subLocality, first.locality].compactMap { $0 }.filter { !$0.isEmpty }.prefix(2).joined(separator: " ")
                if address.isEmpty { address = "家" }
            }
            HomeLocation.stored = HomeLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, address: address)
            message = "已把“\(address)”设为家。约 180 米内会判断为在家。"
        } catch {
            message = "暂时无法获取精确位置，请到窗边或室外再试一次。"
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }
}

extension HomeLocationPicker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.continuation?.resume(returning: location)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
