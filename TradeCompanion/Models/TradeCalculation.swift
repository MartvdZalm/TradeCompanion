import Foundation

nonisolated enum TradeDirection: String, CaseIterable, Identifiable, Sendable {
    case long = "Long"
    case short = "Short"

    var id: String { rawValue }
}

nonisolated enum RiskMode: String, CaseIterable, Identifiable, Sendable {
    case percentage = "Percent"
    case amount = "Amount"

    var id: String { rawValue }
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
    var riskRewardRatio: Decimal

    init(
        accountBalance: Decimal,
        risk: RiskInput,
        direction: TradeDirection,
        entryPrice: Decimal,
        stopLossPrice: Decimal,
        riskRewardRatio: Decimal
    ) {
        self.accountBalance = accountBalance
        self.risk = risk
        self.direction = direction
        self.entryPrice = entryPrice
        self.stopLossPrice = stopLossPrice
        self.riskRewardRatio = riskRewardRatio
    }

    init(
        accountBalance: Decimal,
        riskPercentage: Decimal,
        direction: TradeDirection,
        entryPrice: Decimal,
        stopLossPrice: Decimal,
        riskRewardRatio: Decimal
    ) {
        self.init(
            accountBalance: accountBalance,
            risk: .percentage(riskPercentage),
            direction: direction,
            entryPrice: entryPrice,
            stopLossPrice: stopLossPrice,
            riskRewardRatio: riskRewardRatio
        )
    }
}

nonisolated struct TradeCalculationResult: Equatable, Sendable {
    /// Planned monetary risk, not realized loss.
    var riskAmount: Decimal
    /// Planned risk as a percentage of account balance.
    var riskPercentage: Decimal
    /// Absolute price distance between entry and stop-loss.
    var stopDistance: Decimal
    /// Linear spot-style quantity: risk amount ÷ stop distance.
    var positionQuantity: Decimal
    /// Quantity × entry price. This is not margin.
    var orderValue: Decimal
    var takeProfitPrice: Decimal
    /// Quantity × stop distance. Estimate before fees and slippage.
    var potentialLoss: Decimal
    /// Quantity × (stop distance × risk-to-reward). Estimate before fees and slippage.
    var potentialProfit: Decimal
}

nonisolated enum TradeCalculationError: Equatable, Error, Sendable {
    case missingValue
    case invalidNumber
    case accountBalanceMustBePositive
    case riskPercentageMustBePositive
    case riskAmountMustBePositive
    case entryPriceMustBePositive
    case stopLossPriceMustBePositive
    case riskRewardRatioMustBePositive
    case stopLossMustBeBelowEntryForLong
    case stopLossMustBeAboveEntryForShort
    case stopLossMustDifferFromEntry
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
        case .riskRewardRatioMustBePositive:
            return "Risk-to-reward ratio must be greater than zero."
        case .stopLossMustBeBelowEntryForLong:
            return "For a long trade, stop-loss must be below the entry price."
        case .stopLossMustBeAboveEntryForShort:
            return "For a short trade, stop-loss must be above the entry price."
        case .stopLossMustDifferFromEntry:
            return "Stop-loss must be different from the entry price."
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
    var riskRewardRatio: String
}
