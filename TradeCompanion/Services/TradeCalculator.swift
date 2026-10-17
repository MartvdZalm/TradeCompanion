import Foundation

nonisolated enum TradeCalculator {
    static func calculate(_ input: TradeCalculationInput) -> Result<TradeCalculationResult, TradeCalculationError> {
        guard input.accountBalance > 0 else {
            return .failure(.accountBalanceMustBePositive)
        }

        let riskAmount: Decimal
        let riskPercentage: Decimal
        switch input.risk {
        case .percentage(let percentage):
            guard percentage > 0 else {
                return .failure(.riskPercentageMustBePositive)
            }
            riskPercentage = percentage
            riskAmount = input.accountBalance * percentage / 100
        case .amount(let amount):
            guard amount > 0 else {
                return .failure(.riskAmountMustBePositive)
            }
            riskAmount = amount
            riskPercentage = amount / input.accountBalance * 100
        }

        guard input.entryPrice > 0 else {
            return .failure(.entryPriceMustBePositive)
        }
        guard input.stopLossPrice > 0 else {
            return .failure(.stopLossPriceMustBePositive)
        }
        guard input.riskRewardRatio > 0 else {
            return .failure(.riskRewardRatioMustBePositive)
        }

        switch input.direction {
        case .long where input.stopLossPrice >= input.entryPrice:
            return .failure(
                input.stopLossPrice == input.entryPrice
                    ? .stopLossMustDifferFromEntry
                    : .stopLossMustBeBelowEntryForLong
            )
        case .short where input.stopLossPrice <= input.entryPrice:
            return .failure(
                input.stopLossPrice == input.entryPrice
                    ? .stopLossMustDifferFromEntry
                    : .stopLossMustBeAboveEntryForShort
            )
        default:
            break
        }

        let stopDistance = abs(input.entryPrice - input.stopLossPrice)
        guard stopDistance > 0 else {
            return .failure(.stopLossMustDifferFromEntry)
        }

        let positionQuantity = riskAmount / stopDistance
        let orderValue = positionQuantity * input.entryPrice
        let potentialLoss = positionQuantity * stopDistance
        let potentialProfit = potentialLoss * input.riskRewardRatio
        let takeProfitPrice: Decimal
        switch input.direction {
        case .long:
            takeProfitPrice = input.entryPrice + stopDistance * input.riskRewardRatio
        case .short:
            takeProfitPrice = input.entryPrice - stopDistance * input.riskRewardRatio
        }

        return .success(
            TradeCalculationResult(
                riskAmount: riskAmount,
                riskPercentage: riskPercentage,
                stopDistance: stopDistance,
                positionQuantity: positionQuantity,
                orderValue: orderValue,
                takeProfitPrice: takeProfitPrice,
                potentialLoss: potentialLoss,
                potentialProfit: potentialProfit
            )
        )
    }

    static func parseAndCalculate(
        _ form: TradeFormInput,
        locale: Locale = .current
    ) -> Result<TradeCalculationResult, TradeCalculationError> {
        parse(form, locale: locale).flatMap(calculate)
    }

    static func parse(
        _ form: TradeFormInput,
        locale: Locale = .current
    ) -> Result<TradeCalculationInput, TradeCalculationError> {
        let fields = [
            form.accountBalance,
            form.riskValue,
            form.entryPrice,
            form.stopLossPrice,
            form.riskRewardRatio
        ]

        if fields.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return .failure(.missingValue)
        }

        guard
            let accountBalance = decimal(from: form.accountBalance, locale: locale),
            let riskValue = decimal(from: form.riskValue, locale: locale),
            let entryPrice = decimal(from: form.entryPrice, locale: locale),
            let stopLossPrice = decimal(from: form.stopLossPrice, locale: locale),
            let riskRewardRatio = decimal(from: form.riskRewardRatio, locale: locale)
        else {
            return .failure(.invalidNumber)
        }

        let risk: RiskInput
        switch form.riskMode {
        case .percentage:
            risk = .percentage(riskValue)
        case .amount:
            risk = .amount(riskValue)
        }

        return .success(
            TradeCalculationInput(
                accountBalance: accountBalance,
                risk: risk,
                direction: form.direction,
                entryPrice: entryPrice,
                stopLossPrice: stopLossPrice,
                riskRewardRatio: riskRewardRatio
            )
        )
    }

    static func decimal(from rawValue: String, locale: Locale) -> Decimal? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true

        if let number = formatter.number(from: trimmed) as? NSDecimalNumber, number != .notANumber {
            return number as Decimal
        }

        // Fall back to POSIX parsing so values typed with a period still work
        // in locales that use a comma as the decimal separator.
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}
