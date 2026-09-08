import Foundation

/// An answer to show above the suggestions: the result, plus a restatement of
/// what was understood so a misread query is obvious at a glance.
struct CalcResult: Equatable {
    /// The answer, formatted for reading ("1,234.57").
    let display: String
    /// The answer without grouping separators — what Return puts on the
    /// clipboard, since "1,234.57" rarely pastes usefully anywhere.
    let copyValue: String
    /// The interpretation, e.g. "10 km = 6.21371 mi".
    let detail: String
}

/// Amount + currency pair parsed out of something like "100 usd to ils".
/// Resolved by `CurrencyRatesClient`, which is the only part that needs the
/// network.
struct CurrencyRequest: Equatable {
    let amount: Double
    let from: String
    let to: String
}

/// Offline arithmetic and unit conversion for the search field.
///
/// The expression parser is hand-rolled rather than `NSExpression(format:)`:
/// that format parser understands `FUNCTION(...)`, which can invoke arbitrary
/// selectors on the operands. Pointing it at whatever text someone types (or
/// pastes) into a search field is a code-execution surface for the sake of
/// saving fifty lines of recursive descent.
enum Calculator {
    // MARK: - Entry points

    /// Returns an answer when the text reads as arithmetic or a unit
    /// conversion, and nil for ordinary searches — the caller shows nothing
    /// when there's no answer, so a false positive is worse than a miss.
    static func evaluate(_ text: String) -> CalcResult? {
        if let conversion = unitConversion(text) { return conversion }
        return arithmetic(text)
    }

    /// Currency pairs are recognised here but resolved elsewhere: they're the
    /// one calculation that needs live rates.
    static func currencyRequest(_ text: String) -> CurrencyRequest? {
        guard let parts = conversionParts(text) else { return nil }
        guard unit(for: parts.fromUnit) == nil, unit(for: parts.toUnit) == nil else { return nil }
        guard let from = currencyCode(parts.fromUnit), let to = currencyCode(parts.toUnit) else { return nil }
        return CurrencyRequest(amount: parts.amount, from: from, to: to)
    }

    static func result(for request: CurrencyRequest, rate: Double, asOf: String?) -> CalcResult {
        let converted = request.amount * rate
        let detail = "\(format(request.amount)) \(request.from) = \(format(converted)) \(request.to)"
        return CalcResult(
            display: "\(format(converted)) \(request.to)",
            copyValue: plainFormat(converted),
            detail: asOf.map { "\(detail) · rates \($0)" } ?? detail
        )
    }

    // MARK: - Arithmetic

    private static func arithmetic(_ text: String) -> CalcResult? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let percentOf = percentOf(trimmed) { return percentOf }

        // Require a leading number/paren/sign and at least one operator, so a
        // plain word search never gets treated as a failed calculation.
        guard let first = trimmed.first,
              first.isNumber || first == "(" || first == "-" || first == "." ,
              trimmed.contains(where: { "+-*/×÷^".contains($0) })
        else { return nil }

        var parser = ExpressionParser(trimmed)
        guard let value = parser.parseFully(), value.isFinite else { return nil }
        return CalcResult(
            display: format(value),
            copyValue: plainFormat(value),
            detail: "\(trimmed) ="
        )
    }

    /// "20% of 250" — the one percentage form worth special-casing.
    private static func percentOf(_ text: String) -> CalcResult? {
        let pattern = #"^\s*(-?[\d.,]+)\s*%\s+of\s+(-?[\d.,]+)\s*$"#
        guard let match = firstMatch(pattern, in: text, groups: 2),
              let percent = number(match[0]),
              let base = number(match[1])
        else { return nil }
        let value = base * percent / 100
        return CalcResult(
            display: format(value),
            copyValue: plainFormat(value),
            detail: "\(format(percent))% of \(format(base)) ="
        )
    }

    // MARK: - Unit conversion

    private static func unitConversion(_ text: String) -> CalcResult? {
        guard let parts = conversionParts(text),
              let from = unit(for: parts.fromUnit),
              let to = unit(for: parts.toUnit),
              // Dimensions are tagged by hand because Measurement will happily
              // apply one dimension's converter math to another's units and
              // hand back a confidently wrong number.
              from.dimension == to.dimension
        else { return nil }

        let converted = Measurement(value: parts.amount, unit: from.unit).converted(to: to.unit)
        return CalcResult(
            display: "\(format(converted.value)) \(to.symbol)",
            copyValue: plainFormat(converted.value),
            detail: "\(format(parts.amount)) \(from.symbol) = \(format(converted.value)) \(to.symbol)"
        )
    }

    private struct ConversionParts {
        let amount: Double
        let fromUnit: String
        let toUnit: String
    }

    /// Splits "<amount><unit> to <unit>", also accepting a leading currency
    /// symbol ("$100 to ils") and "in" as the separator.
    private static func conversionParts(_ text: String) -> ConversionParts? {
        let pattern = #"^\s*([$€£₪¥])?\s*(-?[\d][\d,]*(?:\.\d+)?)\s*([a-zA-Z°/²³]{0,14})\s+(?:to|in|as)\s+([$€£₪¥]?[a-zA-Z°/²³]{1,14})\s*$"#
        guard let match = firstMatch(pattern, in: text, groups: 4),
              let amount = number(match[1])
        else { return nil }

        let leadingSymbol = match[0]
        let fromToken = match[2].isEmpty ? leadingSymbol : match[2]
        guard !fromToken.isEmpty else { return nil }
        return ConversionParts(amount: amount, fromUnit: fromToken, toUnit: match[3])
    }

    private struct KnownUnit {
        let dimension: String
        let unit: Dimension
        let symbol: String
    }

    private static func unit(for token: String) -> KnownUnit? {
        unitTable[token.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    private static func currencyCode(_ token: String) -> String? {
        let cleaned = token.trimmingCharacters(in: .whitespaces)
        if let symbol = currencySymbols[cleaned] { return symbol }
        let upper = cleaned.uppercased()
        guard upper.count == 3, upper.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        return upper
    }

    private static let currencySymbols = [
        "$": "USD", "€": "EUR", "£": "GBP", "₪": "ILS", "¥": "JPY",
    ]

    private static let unitTable: [String: KnownUnit] = {
        var table: [String: KnownUnit] = [:]
        func add(_ tokens: [String], _ dimension: String, _ unit: Dimension, _ symbol: String) {
            for token in tokens { table[token] = KnownUnit(dimension: dimension, unit: unit, symbol: symbol) }
        }

        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], "length", UnitLength.kilometers, "km")
        add(["m", "meter", "meters", "metre", "metres"], "length", UnitLength.meters, "m")
        add(["cm", "centimeter", "centimeters"], "length", UnitLength.centimeters, "cm")
        add(["mm", "millimeter", "millimeters"], "length", UnitLength.millimeters, "mm")
        add(["mi", "mile", "miles"], "length", UnitLength.miles, "mi")
        add(["ft", "foot", "feet"], "length", UnitLength.feet, "ft")
        add(["in", "inch", "inches"], "length", UnitLength.inches, "in")
        add(["yd", "yard", "yards"], "length", UnitLength.yards, "yd")
        add(["nmi", "nauticalmile", "nauticalmiles"], "length", UnitLength.nauticalMiles, "nmi")

        add(["kg", "kilo", "kilos", "kilogram", "kilograms"], "mass", UnitMass.kilograms, "kg")
        add(["g", "gram", "grams"], "mass", UnitMass.grams, "g")
        add(["mg", "milligram", "milligrams"], "mass", UnitMass.milligrams, "mg")
        add(["lb", "lbs", "pound", "pounds"], "mass", UnitMass.pounds, "lb")
        add(["oz", "ounce", "ounces"], "mass", UnitMass.ounces, "oz")
        add(["t", "ton", "tons", "tonne", "tonnes"], "mass", UnitMass.metricTons, "t")

        add(["c", "°c", "celsius", "centigrade"], "temperature", UnitTemperature.celsius, "°C")
        add(["f", "°f", "fahrenheit"], "temperature", UnitTemperature.fahrenheit, "°F")
        add(["k", "kelvin"], "temperature", UnitTemperature.kelvin, "K")

        add(["l", "liter", "liters", "litre", "litres"], "volume", UnitVolume.liters, "L")
        add(["ml", "milliliter", "milliliters"], "volume", UnitVolume.milliliters, "mL")
        add(["gal", "gallon", "gallons"], "volume", UnitVolume.gallons, "gal")
        add(["cup", "cups"], "volume", UnitVolume.cups, "cup")
        add(["pt", "pint", "pints"], "volume", UnitVolume.pints, "pt")
        add(["qt", "quart", "quarts"], "volume", UnitVolume.quarts, "qt")
        add(["floz", "fluidounce", "fluidounces"], "volume", UnitVolume.fluidOunces, "fl oz")

        add(["b", "byte", "bytes"], "data", UnitInformationStorage.bytes, "B")
        add(["kb", "kilobyte", "kilobytes"], "data", UnitInformationStorage.kilobytes, "KB")
        add(["mb", "megabyte", "megabytes"], "data", UnitInformationStorage.megabytes, "MB")
        add(["gb", "gigabyte", "gigabytes"], "data", UnitInformationStorage.gigabytes, "GB")
        add(["tb", "terabyte", "terabytes"], "data", UnitInformationStorage.terabytes, "TB")
        add(["kib", "kibibyte", "kibibytes"], "data", UnitInformationStorage.kibibytes, "KiB")
        add(["mib", "mebibyte", "mebibytes"], "data", UnitInformationStorage.mebibytes, "MiB")
        add(["gib", "gibibyte", "gibibytes"], "data", UnitInformationStorage.gibibytes, "GiB")

        add(["s", "sec", "secs", "second", "seconds"], "duration", UnitDuration.seconds, "s")
        add(["min", "mins", "minute", "minutes"], "duration", UnitDuration.minutes, "min")
        add(["h", "hr", "hrs", "hour", "hours"], "duration", UnitDuration.hours, "h")

        add(["kmh", "km/h", "kph"], "speed", UnitSpeed.kilometersPerHour, "km/h")
        add(["mph", "mi/h"], "speed", UnitSpeed.milesPerHour, "mph")
        add(["m/s", "ms"], "speed", UnitSpeed.metersPerSecond, "m/s")
        add(["kn", "knot", "knots"], "speed", UnitSpeed.knots, "kn")

        return table
    }()

    // MARK: - Formatting helpers

    private static let displayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 10
        return formatter
    }()

    private static let plainFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 10
        return formatter
    }()

    static func format(_ value: Double) -> String {
        displayFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func plainFormat(_ value: Double) -> String {
        plainFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    /// Returns the capture groups of the first match, or nil. Groups that
    /// didn't participate come back as empty strings.
    private static func firstMatch(_ pattern: String, in text: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1...groups).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}

/// Recursive-descent parser for `+ - * / × ÷ ^` with parentheses and unary
/// signs. Returns a value only when the *whole* input parsed, so "2+2 apples"
/// is a search, not the number 4.
private struct ExpressionParser {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    mutating func parseFully() -> Double? {
        guard let value = parseExpression() else { return nil }
        skipWhitespace()
        return index == characters.count ? value : nil
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }
        while let op = peekOperator(in: "+-") {
            advance()
            guard let rhs = parseTerm() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parseUnary() else { return nil }
        while let op = peekOperator(in: "*/×÷") {
            advance()
            guard let rhs = parseUnary() else { return nil }
            if op == "*" || op == "×" {
                value *= rhs
            } else {
                guard rhs != 0 else { return nil }
                value /= rhs
            }
        }
        return value
    }

    private mutating func parseUnary() -> Double? {
        skipWhitespace()
        if let character = peek(), character == "-" || character == "+" {
            advance()
            guard let value = parseUnary() else { return nil }
            return character == "-" ? -value : value
        }
        return parsePower()
    }

    private mutating func parsePower() -> Double? {
        guard let base = parsePrimary() else { return nil }
        skipWhitespace()
        guard peek() == "^" else { return base }
        advance()
        guard let exponent = parseUnary() else { return nil }
        let value = pow(base, exponent)
        return value.isFinite ? value : nil
    }

    private mutating func parsePrimary() -> Double? {
        skipWhitespace()
        guard let character = peek() else { return nil }

        if character == "(" {
            advance()
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            guard peek() == ")" else { return nil }
            advance()
            return value
        }

        var digits = ""
        while let character = peek(), character.isNumber || character == "." || character == "," {
            if character != "," { digits.append(character) }
            advance()
        }
        return digits.isEmpty ? nil : Double(digits)
    }

    private mutating func peekOperator(in set: String) -> Character? {
        skipWhitespace()
        guard let character = peek(), set.contains(character) else { return nil }
        return character
    }

    private func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }

    private mutating func advance() {
        index += 1
    }

    private mutating func skipWhitespace() {
        while let character = peek(), character.isWhitespace { advance() }
    }
}
