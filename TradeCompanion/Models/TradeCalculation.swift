import Foundation

nonisolated enum TradeDirection: String, CaseIterable, Identifiable, Sendable {
    case long = "LONG"
    case short = "SHORT"

    var id: String { rawValue }

    var bybitSide: String {
        switch self {
        case .long: return "Buy"
        case .short: return "Sell"
        }
    }
}

nonisolated enum RiskMode: String, CaseIterable, Identifiable, Sendable {
    case percentage = "Percent"
    case amount = "Amount"

    var id: String { rawValue }
}

nonisolated enum OrderEntryType: String, CaseIterable, Identifiable, Sendable {
    case limit = "Limit"
    case market = "Market"

    var id: String { rawValue }

    var bybitOrderType: String { rawValue }
}

nonisolated enum RiskInput: Equatable, Sendable {
    case percentage(Decimal)
    case amount(Decimal)
}

nonisolated struct TradeCalculationInput: Equatable, Sendable {
    var accountBalance: Decimal
    var risk: RiskInput
    var direction: TradeDirection
    var entryPrice: Decimal
    var stopLossPrice: Decimal
    var takeProfitPrice: Decimal
    var constraints: InstrumentConstraints?
    var availableBalance: Decimal?

    init(
        accountBalance: Decimal,
        risk: RiskInput,
        direction: TradeDirection,
        entryPrice: Decimal,
        stopLossPrice: Decimal,
        takeProfitPrice: Decimal,
        constraints: InstrumentConstraints? = nil,
        availableBalance: Decimal? = nil
    ) {
        self.accountBalance = accountBalance
        self.risk = risk
        self.direction = direction
        self.entryPrice = entryPrice
        self.stopLossPrice = stopLossPrice
        self.takeProfitPrice = takeProfitPrice
        self.constraints = constraints
        self.availableBalance = availableBalance
    }

    init(
        accountBalance: Decimal,
        riskPercentage: Decimal,
        direction: TradeDirection,
        entryPrice: Decimal,
        stopLossPrice: Decimal,
        takeProfitPrice: Decimal,
        constraints: InstrumentConstraints? = nil,
        availableBalance: Decimal? = nil
    ) {
        self.init(
            accountBalance: accountBalance,
            risk: .percentage(riskPercentage),
            direction: direction,
            entryPrice: entryPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            constraints: constraints,
            availableBalance: availableBalance
        )
    }
}

nonisolated enum TradeWarning: Equatable, Sendable {
    case quantityRoundedDown
    case estimatedRiskBelowPlanned
    case positionExceedsAvailableBalance
}

nonisolated struct TradeCalculationResult: Equatable, Sendable {
    /// Planned monetary risk from the account settings, before quantity rounding.
    var plannedRiskAmount: Decimal
    /// Planned risk as a percentage of the account balance.
    var riskPercentage: Decimal
    /// Absolute price distance between entry and stop-loss.
    var stopDistance: Decimal
    /// Risk-to-reward ratio based on the entry, stop-loss, and take-profit prices.
    var riskReward: Decimal
    /// Quantity calculated from the planned risk, before exchange rounding.
    var unroundedQuantity: Decimal
    /// Quantity after rounding down to the instrument's increment, if applicable.
    var orderQuantity: Decimal
    /// Order quantity × entry price (notional value).
    var orderValue: Decimal
    /// Potential loss based on order quantity × stop distance, before fees and slippage.
    var potentialLoss: Decimal
    /// Potential profit based on order quantity × take-profit distance, before fees and slippage.
    var potentialProfit: Decimal
    var warnings: [TradeWarning]
    var isExecutable: Bool
}

nonisolated enum TradeCalculationError: Equatable, Error, Sendable {
    case missingValue
    case invalidNumber
    case accountBalanceMustBePositive
    case riskPercentageMustBePositive
    case riskAmountMustBePositive
    case entryPriceMustBePositive
    case stopLossPriceMustBePositive
    case takeProfitPriceMustBePositive
    case stopLossMustBeBelowEntryForLong
    case stopLossMustBeAboveEntryForShort
    case takeProfitMustBeAboveEntryForLong
    case takeProfitMustBeBelowEntryForShort
    case stopLossMustDifferFromEntry
    case takeProfitMustDifferFromEntry
    case unsupportedContractType
    case quantityBelowMinimum
    case quantityAboveMaximum
    case notionalBelowMinimum
    case exitNotionalBelowMinimum
}

extension TradeCalculationError {
    nonisolated var userMessage: String {
        switch self {
        case .missingValue:
            return ""
        case .invalidNumber:
            return "Use a valid number in every field."
        case .accountBalanceMustBePositive:
            return "Account balance must be greater than zero."
        case .riskPercentageMustBePositive:
            return "Risk percentage must be greater than zero."
        case .riskAmountMustBePositive:
            return "Risk amount must be greater than zero."
        case .entryPriceMustBePositive:
            return "Entry price must be greater than zero."
        case .stopLossPriceMustBePositive:
            return "Stop-loss price must be greater than zero."
        case .takeProfitPriceMustBePositive:
            return "Take-profit price must be greater than zero."
        case .stopLossMustBeBelowEntryForLong:
            return "For a LONG trade, stop-loss must be below the entry price."
        case .stopLossMustBeAboveEntryForShort:
            return "For a SHORT trade, stop-loss must be above the entry price."
        case .takeProfitMustBeAboveEntryForLong:
            return "For a LONG trade, take-profit must be above the entry price."
        case .takeProfitMustBeBelowEntryForShort:
            return "For a SHORT trade, take-profit must be below the entry price."
        case .stopLossMustDifferFromEntry:
            return "Stop-loss must be different from the entry price."
        case .takeProfitMustDifferFromEntry:
            return "Take-profit must be different from the entry price."
        case .unsupportedContractType:
            return "This instrument is not a tradable spot pair right now."
        case .quantityBelowMinimum:
            return "The risk-based quantity is below the exchange minimum order size after rounding down."
        case .quantityAboveMaximum:
            return "The calculated quantity exceeds the exchange maximum order size."
        case .notionalBelowMinimum:
            return "The order value is below the exchange minimum order amount."
        case .exitNotionalBelowMinimum:
            return "The stop-loss or take-profit order would be below the exchange minimum order amount at its trigger price. Use a wider risk or a larger size."
        }
    }
}

nonisolated struct TradeFormInput: Equatable, Sendable {
    var accountBalance: String
    var riskMode: RiskMode
    var riskValue: String
    var direction: TradeDirection
    var entryPrice: String
    var stopLossPrice: String
    var takeProfitPrice: String
}
