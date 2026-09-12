import CoreLocation
import Foundation

@MainActor
final class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var symbol = "sun.max.fill"
    @Published private(set) var temperature: String?
    @Published private(set) var condition = "Weather unavailable"
    @Published private(set) var locationName = "Current location"

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locationManager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task {
            await resolvePlace(for: location)
            await load(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        condition = "Location unavailable"
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
        } catch { condition = "Weather unavailable" }
    }

    private func resolvePlace(for location: CLLocation) async {
        do {
            let places = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let place = places.first else { return }
            locationName = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? "Current location"
        } catch { locationName = "Current location" }
    }

    private static func appearance(for code: Int) -> (symbol: String, name: String) {
        switch code {
        case 0: ("sun.max.fill", "Clear")
        case 1...3: ("cloud.sun.fill", "Partly cloudy")
        case 45, 48: ("cloud.fog.fill", "Foggy")
        case 51...57: ("cloud.drizzle.fill", "Drizzle")
        case 61...67, 80...82: ("cloud.rain.fill", "Rain")
        case 71...77, 85, 86: ("cloud.snow.fill", "Snow")
        case 95...99: ("cloud.bolt.rain.fill", "Thunderstorm")
        default: ("cloud.fill", "Cloudy")
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
