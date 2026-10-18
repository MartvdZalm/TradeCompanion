import Foundation

/// Exchange quantity and price rules used to size an order without increasing intended risk.
nonisolated struct InstrumentConstraints: Equatable, Sendable {
    var symbol: String
    var contractType: String      // "Spot" for spot instruments
    var status: String
    var baseCoin: String
    var quoteCoin: String
    var settleCoin: String
    var tickSize: Decimal
    var qtyStep: Decimal          // For spot: basePrecision
    var minOrderQty: Decimal
    var maxOrderQty: Decimal
    var maxMarketOrderQty: Decimal
    var minNotionalValue: Decimal // For spot: minOrderAmt (in quote currency)

    /// The planner formulas (qty = risk / stop distance, loss = qty × distance)
    /// apply to spot and spot margin (short) as long as borrowing interest is ignored.
    var supportsPlannerFormulas: Bool {
        contractType == "Spot" && status.lowercased() == "trading"
    }
}

nonisolated enum ExchangeDecimal {
    static func roundDown(_ value: Decimal, toIncrement increment: Decimal) -> Decimal {
        guard increment > 0 else { return value }
        var steps = value / increment
        var roundedSteps = Decimal()
        NSDecimalRound(&roundedSteps, &steps, 0, .down)
        return roundedSteps * increment
    }

    static func roundUp(_ value: Decimal, toIncrement increment: Decimal) -> Decimal {
        guard increment > 0 else { return value }
        var steps = value / increment
        var roundedSteps = Decimal()
        NSDecimalRound(&roundedSteps, &steps, 0, .up)
        return roundedSteps * increment
    }

    static func roundToNearestIncrement(_ value: Decimal, increment: Decimal) -> Decimal {
        guard increment > 0 else { return value }
        var steps = value / increment
        var roundedSteps = Decimal()
        NSDecimalRound(&roundedSteps, &steps, 0, .plain)
        return roundedSteps * increment
    }

    static func fractionDigits(of increment: Decimal) -> Int {
        let text = formatExact(increment)
        guard let separator = text.firstIndex(of: ".") else { return 0 }
        return text.distance(from: text.index(after: separator), to: text.endIndex)
    }

    static func format(_ value: Decimal, increment: Decimal) -> String {
        let digits = fractionDigits(of: increment)
        var rounded = Decimal()
        var mutable = value
        NSDecimalRound(&rounded, &mutable, digits, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: rounded as NSDecimalNumber) ?? formatExact(rounded)
    }

    static func formatExact(_ value: Decimal) -> String {
        var copy = value
        return NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
    }
}
