import CoreLocation
import Foundation

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    @Published private(set) var symbol = "sun.max.fill"
    @Published private(set) var temperature: String?
    @Published private(set) var condition = "暂时无法获取天气"
    @Published private(set) var locationName = "当前位置"
    @Published private(set) var lastLocation: CLLocation?

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locationManager.requestLocation()
        default: break
        }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        }
    }

    private func handleLocation(_ location: CLLocation) {
        lastLocation = location
        Task {
            await resolvePlace(for: location)
            await load(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
    }

    private func load(latitude: Double, longitude: Double) async {
        let savedUnit = UserDefaults.standard.string(forKey: "weatherUnit") ?? "automatic"
        let fahrenheit = savedUnit == "fahrenheit" || (savedUnit == "automatic" && Locale.current.measurementSystem == .us)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius")
        ]
        guard let url = components.url else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let weather = try JSONDecoder().decode(WeatherResponse.self, from: data).current
            temperature = "\(Int(weather.temperature.rounded()))°"
            let appearance = Self.appearance(for: weather.code)
            symbol = appearance.symbol; condition = appearance.name
        } catch { condition = "暂时无法获取天气" }
    }

    private func resolvePlace(for location: CLLocation) async {
        do {
            let places = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let place = places.first else { return }
            locationName = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? "当前位置"
        } catch { locationName = "当前位置" }
    }

    private static func appearance(for code: Int) -> (symbol: String, name: String) {
        switch code {
        case 0: ("sun.max.fill", "晴")
        case 1...3: ("cloud.sun.fill", "多云")
        case 45, 48: ("cloud.fog.fill", "雾")
        case 51...57: ("cloud.drizzle.fill", "毛毛雨")
        case 61...67, 80...82: ("cloud.rain.fill", "雨")
        case 71...77, 85, 86: ("cloud.snow.fill", "雪")
        case 95...99: ("cloud.bolt.rain.fill", "雷雨")
        default: ("cloud.fill", "阴")
        }
    }
}

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handleLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.condition = "暂时无法获取位置"
        }
    }
}

private struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let code: Int
        enum CodingKeys: String, CodingKey { case temperature = "temperature_2m"; case code = "weather_code" }
    }
    let current: Current
}
