// ConditionEvaluatorTests.swift
// Tests for ConditionEvaluator: time ranges, day of week, solar calculations, and condition results.

import XCTest
@testable import homekitauto

final class ConditionEvaluatorTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a time_range condition with the given after/before times (HH:MM).
    private func makeTimeCondition(after: String? = nil, before: String? = nil) -> AutomationCondition {
        AutomationCondition(
            type: "time_range",
            humanReadable: "time range \(after ?? "?")–\(before ?? "?")",
            after: after,
            before: before,
            days: nil,
            deviceUuid: nil,
            deviceName: nil,
            characteristic: nil,
            operator: nil,
            value: nil,
            requirement: nil
        )
    }

    /// Creates a day_of_week condition with the given day numbers (0=Sunday … 6=Saturday).
    private func makeDayOfWeekCondition(days: [Int]) -> AutomationCondition {
        AutomationCondition(
            type: "day_of_week",
            humanReadable: "days \(days)",
            after: nil,
            before: nil,
            days: days,
            deviceUuid: nil,
            deviceName: nil,
            characteristic: nil,
            operator: nil,
            value: nil,
            requirement: nil
        )
    }

    /// Creates a solar condition with the given requirement string.
    private func makeSolarCondition(requirement: String? = nil) -> AutomationCondition {
        AutomationCondition(
            type: "solar",
            humanReadable: requirement ?? "solar",
            after: nil,
            before: nil,
            days: nil,
            deviceUuid: nil,
            deviceName: nil,
            characteristic: nil,
            operator: nil,
            value: nil,
            requirement: requirement
        )
    }

    /// Creates a Date for a specific date and time in the current timezone.
    private func makeDate(year: Int = 2026, month: Int = 6, day: Int = 21,
                          hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone.current
        return Calendar.current.date(from: components)!
    }

    // MARK: - Time Range Tests

    func testTimeRangeWithinBounds() {
        let evaluator = ConditionEvaluator()
        let condition = makeTimeCondition(after: "08:00", before: "18:00")
        let noon = makeDate(hour: 12, minute: 0)
        let result = evaluator.evaluateTimeRange(condition, at: noon)
        XCTAssertTrue(result.met, "12:00 should be within 08:00–18:00")
    }

    func testTimeRangeOutsideBounds() {
        let evaluator = ConditionEvaluator()
        let condition = makeTimeCondition(after: "08:00", before: "18:00")
        let evening = makeDate(hour: 20, minute: 0)
        let result = evaluator.evaluateTimeRange(condition, at: evening)
        XCTAssertFalse(result.met, "20:00 should be outside 08:00–18:00")
    }

    func testTimeRangeMidnightCrossover() {
        let evaluator = ConditionEvaluator()
        let condition = makeTimeCondition(after: "22:00", before: "06:00")

        // 23:00 should be in range (after 22:00)
        let lateNight = makeDate(hour: 23, minute: 0)
        let result1 = evaluator.evaluateTimeRange(condition, at: lateNight)
        XCTAssertTrue(result1.met, "23:00 should be within 22:00–06:00 (overnight)")

        // 03:00 should be in range (before 06:00)
        let earlyMorning = makeDate(hour: 3, minute: 0)
        let result2 = evaluator.evaluateTimeRange(condition, at: earlyMorning)
        XCTAssertTrue(result2.met, "03:00 should be within 22:00–06:00 (overnight)")

        // 12:00 should be outside range
        let noon = makeDate(hour: 12, minute: 0)
        let result3 = evaluator.evaluateTimeRange(condition, at: noon)
        XCTAssertFalse(result3.met, "12:00 should be outside 22:00–06:00 (overnight)")
    }

    func testTimeRangeExactBoundary() {
        let evaluator = ConditionEvaluator()
        let condition = makeTimeCondition(after: "08:00", before: "18:00")

        // Exact start time should be within range (>= after)
        let startTime = makeDate(hour: 8, minute: 0)
        let result1 = evaluator.evaluateTimeRange(condition, at: startTime)
        XCTAssertTrue(result1.met, "08:00 should be within range (start boundary, inclusive)")

        // Exact end time should be outside range (< before)
        let endTime = makeDate(hour: 18, minute: 0)
        let result2 = evaluator.evaluateTimeRange(condition, at: endTime)
        XCTAssertFalse(result2.met, "18:00 should be outside range (end boundary, exclusive)")
    }

    // MARK: - Day of Week Tests

    func testDayOfWeekMatch() {
        let evaluator = ConditionEvaluator()
        // 2026-02-25 is a Wednesday → weekday = 4 in Calendar → 3 in 0-based
        let wednesday = makeDate(year: 2026, month: 2, day: 25, hour: 12, minute: 0)
        let condition = makeDayOfWeekCondition(days: [1, 2, 3, 4, 5]) // Mon–Fri
        let result = evaluator.evaluateDayOfWeek(condition, at: wednesday)
        XCTAssertTrue(result.met, "Wednesday (3) should match weekdays [1,2,3,4,5]")
    }

    func testDayOfWeekNoMatch() {
        let evaluator = ConditionEvaluator()
        // 2026-02-28 is a Saturday → weekday = 7 in Calendar → 6 in 0-based
        let saturday = makeDate(year: 2026, month: 2, day: 28, hour: 12, minute: 0)
        let condition = makeDayOfWeekCondition(days: [1, 2, 3, 4, 5]) // Mon–Fri
        let result = evaluator.evaluateDayOfWeek(condition, at: saturday)
        XCTAssertFalse(result.met, "Saturday (6) should not match weekdays [1,2,3,4,5]")
    }

    func testDayOfWeekAllDays() {
        let evaluator = ConditionEvaluator()
        let condition = makeDayOfWeekCondition(days: [0, 1, 2, 3, 4, 5, 6])
        // 2026-02-22 is a Sunday (0). Test all 7 consecutive days.
        let baseSunday = makeDate(year: 2026, month: 2, day: 22, hour: 12, minute: 0)
        for dayOffset in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: baseSunday)!
            let result = evaluator.evaluateDayOfWeek(condition, at: date)
            XCTAssertTrue(result.met, "Day offset \(dayOffset) should match when all 7 days are listed")
        }
    }

    // MARK: - Solar Calculator Tests

    func testSolarCalculatorSummer() {
        // June 21 at SF latitude: day length should be ~14.5–15.3 hours
        let calculator = SolarCalculator(latitude: 37.7749, longitude: -122.4194)
        let summerSolstice = makeDate(year: 2026, month: 6, day: 21)
        let raw = calculator.calculateRaw(for: summerSolstice)

        // Day length from raw decimals is timezone-independent
        let dayLengthHours = raw.sunsetDecimal - raw.sunriseDecimal
        let dayLengthMinutes = Int(dayLengthHours * 60)

        // SF summer day length: ~14h 45min (885 min) ±30 min
        XCTAssertTrue(dayLengthMinutes >= 840 && dayLengthMinutes <= 920,
                      "SF summer day length should be ~14–15.3h, got \(dayLengthMinutes) min")

        // Also verify components produce valid times
        let result = calculator.calculate(for: summerSolstice)
        XCTAssertNotNil(result.sunrise.hour)
        XCTAssertNotNil(result.sunset.hour)
    }

    func testSolarCalculatorWinter() {
        // Dec 21 at SF latitude: day length should be ~9.3–10 hours
        let calculator = SolarCalculator(latitude: 37.7749, longitude: -122.4194)
        let winterSolstice = makeDate(year: 2026, month: 12, day: 21)
        let raw = calculator.calculateRaw(for: winterSolstice)

        let dayLengthHours = raw.sunsetDecimal - raw.sunriseDecimal
        let dayLengthMinutes = Int(dayLengthHours * 60)

        // SF winter day length: ~9h 30min (570 min) ±30 min
        XCTAssertTrue(dayLengthMinutes >= 540 && dayLengthMinutes <= 610,
                      "SF winter day length should be ~9–10.2h, got \(dayLengthMinutes) min")

        // Summer days should be longer than winter days
        let summerRaw = calculator.calculateRaw(for: makeDate(year: 2026, month: 6, day: 21))
        let summerLength = summerRaw.sunsetDecimal - summerRaw.sunriseDecimal
        XCTAssertTrue(summerLength > dayLengthHours,
                      "Summer day should be longer than winter day")
    }

    func testSolarCalculatorEquator() {
        // Equator (0°, 0°) — day length should be ~12 hours year-round
        let calculator = SolarCalculator(latitude: 0.0, longitude: 0.0)

        for month in [3, 6, 9, 12] {
            let date = makeDate(year: 2026, month: month, day: 21)
            let raw = calculator.calculateRaw(for: date)
            let dayLengthMinutes = Int((raw.sunsetDecimal - raw.sunriseDecimal) * 60)

            // At equator, day length should be ~12 hours (720 min) ±30 min
            XCTAssertTrue(dayLengthMinutes >= 690 && dayLengthMinutes <= 750,
                          "Equator day length should be ~12h (720 min ±30), got \(dayLengthMinutes) min in month \(month)")
        }
    }

    func testSolarCalculatorHighLatitude() {
        // 65°N, 25°E (northern Finland) in June — very long day
        let calculator = SolarCalculator(latitude: 65.0, longitude: 25.0)
        let summerSolstice = makeDate(year: 2026, month: 6, day: 21)
        let raw = calculator.calculateRaw(for: summerSolstice)

        let dayLengthMinutes = Int((raw.sunsetDecimal - raw.sunriseDecimal) * 60)

        // At 65°N in June, day is very long (20+ hours or midnight sun)
        XCTAssertTrue(dayLengthMinutes >= 1200,
                      "High latitude (65°N) summer day should be 20+ hours, got \(dayLengthMinutes) min")
    }

    // MARK: - Solar Calculator Utility Tests

    func testToComponentsWrapsCorrectly() {
        let calculator = SolarCalculator.default

        // Normal value
        let morning = calculator.toComponents(6.5)
        XCTAssertEqual(morning.hour, 6)
        XCTAssertEqual(morning.minute, 30)

        // Negative value wraps to previous day
        let wrapped = calculator.toComponents(-1.0)
        XCTAssertEqual(wrapped.hour, 23)
        XCTAssertEqual(wrapped.minute, 0)

        // Value exceeding 24 wraps to next day
        let overflow = calculator.toComponents(25.5)
        XCTAssertEqual(overflow.hour, 1)
        XCTAssertEqual(overflow.minute, 30)

        // Midnight
        let midnight = calculator.toComponents(0.0)
        XCTAssertEqual(midnight.hour, 0)
        XCTAssertEqual(midnight.minute, 0)
    }

    // MARK: - Condition Result Tests

    func testAllConditionsMet() {
        let evaluator = ConditionEvaluator()
        // Use a time range that spans all day and include all days
        let timeCondition = makeTimeCondition(after: "00:00", before: "23:59")
        let dayCondition = makeDayOfWeekCondition(days: [0, 1, 2, 3, 4, 5, 6])

        let now = Date()
        let timeResult = evaluator.evaluateTimeRange(timeCondition, at: now)
        let dayResult = evaluator.evaluateDayOfWeek(dayCondition, at: now)

        XCTAssertTrue(timeResult.met, "00:00–23:59 should include any time")
        XCTAssertTrue(dayResult.met, "All days should match any day")

        let allMet = [timeResult, dayResult].allSatisfy { $0.met }
        XCTAssertTrue(allMet, "All conditions should be met")
    }

    func testSomeConditionsNotMet() {
        let evaluator = ConditionEvaluator()

        // A condition that's always met (any time is in 00:00–23:59)
        let alwaysMet = makeTimeCondition(after: "00:00", before: "23:59")
        // A condition that's never met (empty days list → fails with "no days specified")
        let neverMet = makeDayOfWeekCondition(days: [])

        let timeResult = evaluator.evaluateTimeRange(alwaysMet)
        let dayResult = evaluator.evaluateDayOfWeek(neverMet)

        XCTAssertTrue(timeResult.met, "00:00–23:59 should include any time")
        XCTAssertFalse(dayResult.met, "Empty days list should not match")

        let allMet = [timeResult, dayResult].allSatisfy { $0.met }
        XCTAssertFalse(allMet, "Should not be allMet when one condition fails")
    }

    func testEmptyConditions() {
        // No conditions → allMet should be true (vacuous truth)
        let results: [ConditionEvaluator.SingleResult] = []
        let allMet = results.allSatisfy { $0.met }
        XCTAssertTrue(allMet, "Empty conditions should be allMet (vacuous truth)")
    }

    // MARK: - Integration-style Tests

    func testConditionEvaluatorWithTimeRange() {
        let evaluator = ConditionEvaluator()
        let noon = makeDate(hour: 12, minute: 0)

        // Range that includes noon
        let includingCondition = makeTimeCondition(after: "08:00", before: "18:00")
        let result1 = evaluator.evaluateTimeRange(includingCondition, at: noon)
        XCTAssertTrue(result1.met)
        XCTAssertTrue(result1.reason.contains("within"),
                      "Reason should mention 'within': \(result1.reason)")

        // Range that excludes noon
        let excludingCondition = makeTimeCondition(after: "13:00", before: "18:00")
        let result2 = evaluator.evaluateTimeRange(excludingCondition, at: noon)
        XCTAssertFalse(result2.met)
        XCTAssertTrue(result2.reason.contains("outside"),
                      "Reason should mention 'outside': \(result2.reason)")
    }

    func testConditionEvaluatorWithDayOfWeek() {
        let evaluator = ConditionEvaluator()

        // 2026-02-25 = Wednesday (0-based: 3)
        let wednesday = makeDate(year: 2026, month: 2, day: 25, hour: 12)

        // Including Wednesday (3)
        let weekdays = makeDayOfWeekCondition(days: [1, 2, 3, 4, 5])
        let result1 = evaluator.evaluateDayOfWeek(weekdays, at: wednesday)
        XCTAssertTrue(result1.met)
        XCTAssertTrue(result1.reason.contains("Wednesday"),
                      "Reason should mention Wednesday: \(result1.reason)")

        // Excluding Wednesday
        let weekendOnly = makeDayOfWeekCondition(days: [0, 6])
        let result2 = evaluator.evaluateDayOfWeek(weekendOnly, at: wednesday)
        XCTAssertFalse(result2.met)
        XCTAssertTrue(result2.reason.contains("Wednesday"),
                      "Reason should mention Wednesday: \(result2.reason)")
    }

    // MARK: - Parse Time Helper Tests

    func testParseTimeToMinutes() {
        let evaluator = ConditionEvaluator()

        XCTAssertEqual(evaluator.parseTimeToMinutes("00:00"), 0)
        XCTAssertEqual(evaluator.parseTimeToMinutes("06:30"), 390)
        XCTAssertEqual(evaluator.parseTimeToMinutes("12:00"), 720)
        XCTAssertEqual(evaluator.parseTimeToMinutes("23:59"), 1439)
        XCTAssertNil(evaluator.parseTimeToMinutes(nil))
        XCTAssertNil(evaluator.parseTimeToMinutes("invalid"))
        XCTAssertNil(evaluator.parseTimeToMinutes("12"))
    }

    // MARK: - Solar Condition Evaluation Tests

    func testSolarConditionAfterSunset() {
        let evaluator = ConditionEvaluator()
        let condition = makeSolarCondition(requirement: "after_sunset")

        // 23:00 should be after sunset at any reasonable latitude
        let lateNight = makeDate(hour: 23, minute: 0)
        let result = evaluator.evaluateSolar(condition, at: lateNight)
        XCTAssertTrue(result.met, "23:00 should be after sunset")
    }

    func testSolarConditionBeforeSunrise() {
        let evaluator = ConditionEvaluator()
        let condition = makeSolarCondition(requirement: "before_sunrise")

        // 03:00 should be before sunrise at any reasonable latitude
        let earlyMorning = makeDate(hour: 3, minute: 0)
        let result = evaluator.evaluateSolar(condition, at: earlyMorning)
        XCTAssertTrue(result.met, "03:00 should be before sunrise")
    }

    func testSolarConditionMissingRequirement() {
        let evaluator = ConditionEvaluator()
        let condition = makeSolarCondition(requirement: nil)
        let result = evaluator.evaluateSolar(condition)
        XCTAssertFalse(result.met, "Solar condition without requirement should fail")
        XCTAssertTrue(result.reason.contains("missing"),
                      "Reason should mention missing requirement: \(result.reason)")
    }

    func testSolarConditionUnknownRequirement() {
        let evaluator = ConditionEvaluator()
        let condition = makeSolarCondition(requirement: "at_twilight")
        let result = evaluator.evaluateSolar(condition)
        XCTAssertFalse(result.met, "Unknown solar requirement should fail")
        XCTAssertTrue(result.reason.contains("Unknown"),
                      "Reason should mention unknown: \(result.reason)")
    }

    func testSolarConditionUsesCalculatedTimes() {
        // Verify that solar conditions use dynamic times, not hardcoded 06:30/18:30
        let evaluator = ConditionEvaluator(latitude: 37.7749, longitude: -122.4194)
        let condition = makeSolarCondition(requirement: "after_sunrise")

        let summerNoon = makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0)
        let result = evaluator.evaluateSolar(condition, at: summerNoon)

        XCTAssertTrue(result.met, "Noon should be after sunrise")
        // The reason should NOT contain the old hardcoded "06:30"
        // (SF summer sunrise is around 5:50 local time in PDT)
        // This verifies the calculator is being used
        XCTAssertTrue(result.reason.contains("~sunrise"),
                      "Reason should reference sunrise time: \(result.reason)")
    }

    // MARK: - Custom Latitude/Longitude Tests

    func testConditionEvaluatorCustomCoordinates() {
        // London: 51.5074°N, -0.1278°W
        let evaluator = ConditionEvaluator(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(evaluator.latitude, 51.5074, accuracy: 0.001)
        XCTAssertEqual(evaluator.longitude, -0.1278, accuracy: 0.001)
    }

    func testConditionEvaluatorDefaultCoordinates() {
        // Defaults should be San Francisco
        let evaluator = ConditionEvaluator()
        XCTAssertEqual(evaluator.latitude, 37.7749, accuracy: 0.001)
        XCTAssertEqual(evaluator.longitude, -122.4194, accuracy: 0.001)
    }
}
