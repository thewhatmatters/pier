import CoreLocation
import Foundation
import WeatherKit

struct WeatherPlace: Codable, Equatable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }

    var location: Weather.Location {
        Weather.Location(latitude: latitude, longitude: longitude, city: name)
    }
}

enum WeatherTarget: Equatable {
    case here
    case place(WeatherPlace)
}

enum Weather {
    struct Location: Equatable {
        var latitude: Double
        var longitude: Double
        var city: String

        var clLocation: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    static func condition(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunder"
        case 96, 99: return "Hail"
        default: return "Weather"
        }
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func snapshot(from data: Data, city: String) throws -> WeatherSnapshot {
        let decoded = try JSONDecoder().decode(Forecast.self, from: data)
        let code = decoded.current.weather_code
        return WeatherSnapshot(
            temperature: Int(decoded.current.temperature_2m.rounded()),
            high: decoded.daily?.temperature_2m_max?.first.map { Int($0.rounded()) },
            low: decoded.daily?.temperature_2m_min?.first.map { Int($0.rounded()) },
            condition: condition(for: code),
            symbol: symbol(for: code),
            city: city,
            source: "Open-Meteo"
        )
    }

    static func location(from data: Data) throws -> Location {
        let decoded = try JSONDecoder().decode(IPLocation.self, from: data)
        guard decoded.success != false else {
            throw URLError(.cannotParseResponse)
        }
        return Location(latitude: decoded.latitude, longitude: decoded.longitude, city: decoded.city)
    }

    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components.url!
    }

    static let ipLocationURL = URL(string: "https://ipwho.is/")!

    static func snapshot(
        from current: CurrentWeather,
        high: Measurement<UnitTemperature>? = nil,
        low: Measurement<UnitTemperature>? = nil,
        city: String
    ) -> WeatherSnapshot {
        let fahrenheit = current.temperature.converted(to: .fahrenheit).value
        return WeatherSnapshot(
            temperature: Int(fahrenheit.rounded()),
            high: high.map { Int($0.converted(to: .fahrenheit).value.rounded()) },
            low: low.map { Int($0.converted(to: .fahrenheit).value.rounded()) },
            condition: conditionLabel(current.condition),
            symbol: filledSymbol(current.symbolName),
            city: city,
            source: "Apple Weather"
        )
    }

    static func filledSymbol(_ name: String) -> String {
        name.hasSuffix(".fill") ? name : "\(name).fill"
    }

    static func conditionLabel(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .hot: return "Clear"
        case .mostlyClear: return "Mostly clear"
        case .partlyCloudy: return "Partly cloudy"
        case .mostlyCloudy: return "Mostly cloudy"
        case .cloudy: return "Cloudy"
        case .foggy, .haze, .smoky: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain, .heavyRain, .sunShowers: return "Rain"
        case .freezingDrizzle, .freezingRain: return "Freezing rain"
        case .snow, .heavySnow, .flurries, .sunFlurries, .blowingSnow: return "Snow"
        case .wintryMix, .sleet: return "Wintry mix"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return "Thunder"
        case .hail: return "Hail"
        case .windy, .breezy, .blowingDust: return "Windy"
        case .blizzard, .frigid: return "Snow"
        case .hurricane, .tropicalStorm: return "Storm"
        @unknown default: return "Weather"
        }
    }

    @MainActor
    static func fetch(target: WeatherTarget = .here) async -> WeatherSnapshot? {
        switch target {
        case .here:
            let location = await resolveLocation()
            if let location, let apple = await fetchApple(for: location) {
                return apple
            }
            return await fetchOpenMeteo(location: location)
        case .place(let place):
            if let apple = await fetchApple(for: place.location) {
                return apple
            }
            return await fetchOpenMeteo(location: place.location)
        }
    }

    static func lookupCity(_ query: String) async -> WeatherPlace? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let marks = try await CLGeocoder().geocodeAddressString(trimmed)
            guard let mark = marks.first, let location = mark.location else { return nil }
            let name = mark.locality ?? mark.name ?? trimmed
            return WeatherPlace(
                name: name,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } catch {
            return nil
        }
    }

    @MainActor
    private static func resolveLocation() async -> Location? {
        if let device = await LocationSource.shared.current() {
            let city = await cityName(for: device) ?? "Here"
            return Location(latitude: device.coordinate.latitude, longitude: device.coordinate.longitude, city: city)
        }
        do {
            let (ipData, _) = try await URLSession.shared.data(from: ipLocationURL)
            return try location(from: ipData)
        } catch {
            NSLog("Pier: location failed — \(error.localizedDescription)")
            return nil
        }
    }

    private static func cityName(for location: CLLocation) async -> String? {
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            return marks.first?.locality
        } catch {
            return nil
        }
    }

    private static func fetchApple(for location: Location) async -> WeatherSnapshot? {
        do {
            let weather = try await WeatherService.shared.weather(for: location.clLocation)
            let today = weather.dailyForecast.first
            return snapshot(
                from: weather.currentWeather,
                high: today?.highTemperature,
                low: today?.lowTemperature,
                city: location.city
            )
        } catch {
            NSLog("Pier: WeatherKit failed — \(error.localizedDescription)")
            return nil
        }
    }

    private static func fetchOpenMeteo(location: Location?) async -> WeatherSnapshot? {
        do {
            let resolved = try await resolvedLocation(location)
            let (weatherData, _) = try await URLSession.shared.data(
                from: forecastURL(latitude: resolved.latitude, longitude: resolved.longitude)
            )
            return try snapshot(from: weatherData, city: resolved.city)
        } catch {
            NSLog("Pier: Open-Meteo fallback failed — \(error.localizedDescription)")
            return nil
        }
    }

    private static func resolvedLocation(_ location: Location?) async throws -> Location {
        if let location { return location }
        let (ipData, _) = try await URLSession.shared.data(from: ipLocationURL)
        return try self.location(from: ipData)
    }

    private struct Forecast: Decodable {
        var current: Current
        var daily: Daily?
        struct Current: Decodable {
            var temperature_2m: Double
            var weather_code: Int
        }
        struct Daily: Decodable {
            var temperature_2m_max: [Double]?
            var temperature_2m_min: [Double]?
        }
    }

    private struct IPLocation: Decodable {
        var success: Bool?
        var latitude: Double
        var longitude: Double
        var city: String
    }
}

/// One manager, kept alive so the authorization prompt can complete.
@MainActor
final class LocationSource: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationSource()

    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 300 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            if pending != nil {
                continuation.resume(returning: manager.location)
                return
            }
            pending = continuation
            if manager.authorizationStatus != .notDetermined {
                manager.requestLocation()
            }
            let timeout: Double = manager.authorizationStatus == .notDetermined ? 45 : 8
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                finish(with: manager.location)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Pier: Core Location failed — \(error.localizedDescription)")
        finish(with: manager.location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            finish(with: nil)
        }
    }

    private func finish(with location: CLLocation?) {
        guard let pending else { return }
        self.pending = nil
        pending.resume(returning: location)
    }
}
