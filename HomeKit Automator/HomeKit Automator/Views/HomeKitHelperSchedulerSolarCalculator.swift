// SolarCalculator.swift
// Calculates sunrise and sunset times for a given location.
// Based on NOAA Solar Calculator algorithm.

import Foundation
import CoreLocation

/// Calculates solar events (sunrise, sunset) for a location.
struct SolarCalculator {
    
    let latitude: Double
    let longitude: Double
    let timezone: TimeZone
    
    init(latitude: Double, longitude: Double, timezone: TimeZone = .current) {
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
    }
    
    /// Convenience initializer from CLLocationCoordinate2D.
    init(coordinate: CLLocationCoordinate2D, timezone: TimeZone = .current) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timezone = timezone
    }
    
    // MARK: - Public API
    
    /// Calculates sunrise time for a given date.
    func sunrise(on date: Date) -> Date? {
        calculateSolarEvent(on: date, rising: true)
    }
    
    /// Calculates sunset time for a given date.
    func sunset(on date: Date) -> Date? {
        calculateSolarEvent(on: date, rising: false)
    }
    
    /// Calculates both sunrise and sunset for a date.
    func solarEvents(on date: Date) -> (sunrise: Date?, sunset: Date?) {
        (sunrise(on: date), sunset(on: date))
    }
    
    // MARK: - Calculation
    
    private func calculateSolarEvent(on date: Date, rising: Bool) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        
        // Calculate Julian Day
        let jd = julianDay(year: year, month: month, day: day)
        
        // Calculate solar noon
        let solarNoon = calculateSolarNoon(jd: jd)
        
        // Calculate sunrise/sunset
        let solarEvent = rising ? calculateSunrise(jd: jd, solarNoon: solarNoon) :
                                  calculateSunset(jd: jd, solarNoon: solarNoon)
        
        guard let eventTime = solarEvent else {
            return nil
        }
        
        // Convert to Date
        var resultComponents = components
        let hours = Int(eventTime)
        let minutes = Int((eventTime - Double(hours)) * 60)
        resultComponents.hour = hours
        resultComponents.minute = minutes
        resultComponents.second = 0
        
        return calendar.date(from: resultComponents)
    }
    
    // MARK: - Julian Day
    
    private func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        
        if m <= 2 {
            y -= 1
            m += 12
        }
        
        let a = y / 100
        let b = 2 - a + (a / 4)
        
        let jd = Double(Int(365.25 * Double(y + 4716))) +
                 Double(Int(30.6001 * Double(m + 1))) +
                 Double(day + b) - 1524.5
        
        return jd
    }
    
    // MARK: - Solar Noon
    
    private func calculateSolarNoon(jd: Double) -> Double {
        // Century from J2000.0
        let t = (jd - 2451545.0) / 36525.0
        
        // Mean longitude of the sun
        var L0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        L0 = fmod(L0, 360.0)
        if L0 < 0 { L0 += 360.0 }
        
        // Mean anomaly
        var M = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        M = fmod(M, 360.0)
        
        // Equation of center
        let C = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(M * .pi / 180.0) +
                (0.019993 - 0.000101 * t) * sin(2 * M * .pi / 180.0) +
                0.000289 * sin(3 * M * .pi / 180.0)
        
        // True longitude
        let theta = L0 + C
        
        // Equation of time (minutes)
        let epsilon = 23.439 - 0.0000004 * t
        let y = tan(epsilon * .pi / 360.0) * tan(epsilon * .pi / 360.0)
        
        let eqTime = 4.0 * (y * sin(2 * L0 * .pi / 180.0) -
                            2 * 0.016708 * sin(M * .pi / 180.0) +
                            4 * 0.016708 * y * sin(M * .pi / 180.0) * cos(2 * L0 * .pi / 180.0) -
                            0.5 * y * y * sin(4 * L0 * .pi / 180.0) -
                            1.25 * 0.016708 * 0.016708 * sin(2 * M * .pi / 180.0)) * 180.0 / .pi
        
        // Solar noon (hours)
        let solarNoon = (720.0 - 4.0 * longitude - eqTime) / 60.0
        
        return solarNoon
    }
    
    // MARK: - Sunrise/Sunset
    
    private func calculateSunrise(jd: Double, solarNoon: Double) -> Double? {
        calculateSolarEventTime(jd: jd, solarNoon: solarNoon, rising: true)
    }
    
    private func calculateSunset(jd: Double, solarNoon: Double) -> Double? {
        calculateSolarEventTime(jd: jd, solarNoon: solarNoon, rising: false)
    }
    
    private func calculateSolarEventTime(jd: Double, solarNoon: Double, rising: Bool) -> Double? {
        // Century from J2000.0
        let t = (jd - 2451545.0) / 36525.0
        
        // Sun's declination
        let M = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        let L0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let C = (1.914602 - 0.004817 * t) * sin(M * .pi / 180.0)
        let theta = L0 + C
        let lambda = theta - 0.00569 - 0.00478 * sin((125.04 - 1934.136 * t) * .pi / 180.0)
        
        let epsilon = 23.439 - 0.0000004 * t
        let declination = asin(sin(epsilon * .pi / 180.0) * sin(lambda * .pi / 180.0)) * 180.0 / .pi
        
        // Hour angle
        let zenith = 90.833 // Official zenith (90° + 50' for refraction)
        
        let cosHA = (cos(zenith * .pi / 180.0) -
                     sin(latitude * .pi / 180.0) * sin(declination * .pi / 180.0)) /
                    (cos(latitude * .pi / 180.0) * cos(declination * .pi / 180.0))
        
        // Check if sun rises/sets
        guard cosHA >= -1.0 && cosHA <= 1.0 else {
            return nil // Polar day/night
        }
        
        let HA = acos(cosHA) * 180.0 / .pi
        let offset = HA / 15.0 // Convert to hours
        
        return rising ? (solarNoon - offset) : (solarNoon + offset)
    }
}

// MARK: - Solar Event

/// Represents a solar event with an optional offset.
struct SolarEvent {
    let type: EventType
    let offsetMinutes: Int
    
    enum EventType {
        case sunrise
        case sunset
    }
    
    /// Calculates the actual event time for a given date and location.
    func calculateTime(on date: Date, calculator: SolarCalculator) -> Date? {
        let baseTime: Date?
        
        switch type {
        case .sunrise:
            baseTime = calculator.sunrise(on: date)
        case .sunset:
            baseTime = calculator.sunset(on: date)
        }
        
        guard let time = baseTime else {
            return nil
        }
        
        // Apply offset
        return Calendar.current.date(byAdding: .minute, value: offsetMinutes, to: time)
    }
}

// MARK: - Default Locations

extension SolarCalculator {
    /// San Francisco, CA
    static let sanFrancisco = SolarCalculator(
        latitude: 37.7749,
        longitude: -122.4194
    )
    
    /// New York, NY
    static let newYork = SolarCalculator(
        latitude: 40.7128,
        longitude: -74.0060
    )
    
    /// London, UK
    static let london = SolarCalculator(
        latitude: 51.5074,
        longitude: -0.1278
    )
    
    /// Creates calculator for current device location (requires location services).
    static func current(completion: @escaping (SolarCalculator?) -> Void) {
        // Would use CLLocationManager here
        // For now, return San Francisco as default
        completion(.sanFrancisco)
    }
}
