import Foundation

nonisolated enum TradeValueFormatting {
    static func money(_ value: Decimal, currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    static func percent(_ value: Decimal, locale: Locale = .current) -> String {
        let formatted = decimal(value, maximumFractionDigits: 4, locale: locale)
        return "\(formatted)%"
    }

    static func decimal(_ value: Decimal, maximumFractionDigits: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }
}
