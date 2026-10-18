import Foundation

nonisolated enum TradeCalculator {
    static func calculate(_ input: TradeCalculationInput) -> Result<TradeCalculationResult, TradeCalculationError> {
        guard input.accountBalance > 0 else {
            return .failure(.accountBalanceMustBePositive)
        }

        let plannedRiskAmount: Decimal
        let riskPercentage: Decimal
        switch input.risk {
        case .percentage(let percentage):
            guard percentage > 0 else {
                return .failure(.riskPercentageMustBePositive)
            }
            riskPercentage = percentage
            plannedRiskAmount = input.accountBalance * percentage / 100
        case .amount(let amount):
            guard amount > 0 else {
                return .failure(.riskAmountMustBePositive)
            }
            plannedRiskAmount = amount
            riskPercentage = amount / input.accountBalance * 100
        }

        guard input.entryPrice > 0 else {
            return .failure(.entryPriceMustBePositive)
        }
        guard input.stopLossPrice > 0 else {
            return .failure(.stopLossPriceMustBePositive)
        }
        guard input.takeProfitPrice > 0 else {
            return .failure(.takeProfitPriceMustBePositive)
        }

        switch input.direction {
        case .long where input.stopLossPrice >= input.entryPrice:
            return .failure(
                input.stopLossPrice == input.entryPrice
                    ? .stopLossMustDifferFromEntry
                    : .stopLossMustBeBelowEntryForLong
            )
        case .long where input.takeProfitPrice <= input.entryPrice:
            return .failure(
                input.takeProfitPrice == input.entryPrice
                    ? .takeProfitMustDifferFromEntry
                    : .takeProfitMustBeAboveEntryForLong
            )
        case .short where input.stopLossPrice <= input.entryPrice:
            return .failure(
                input.stopLossPrice == input.entryPrice
                    ? .stopLossMustDifferFromEntry
                    : .stopLossMustBeAboveEntryForShort
            )
        case .short where input.takeProfitPrice >= input.entryPrice:
            return .failure(
                input.takeProfitPrice == input.entryPrice
                    ? .takeProfitMustDifferFromEntry
                    : .takeProfitMustBeBelowEntryForShort
            )
        default:
            break
        }

        if let constraints = input.constraints, !constraints.supportsPlannerFormulas {
            return .failure(.unsupportedContractType)
        }

        let stopDistance = abs(input.entryPrice - input.stopLossPrice)
        guard stopDistance > 0 else {
            return .failure(.stopLossMustDifferFromEntry)
        }

        let takeProfitDistance = abs(input.takeProfitPrice - input.entryPrice)
        guard takeProfitDistance > 0 else {
            return .failure(.takeProfitMustDifferFromEntry)
        }

        let riskReward = takeProfitDistance / stopDistance
        let unroundedQuantity = plannedRiskAmount / stopDistance

        var warnings: [TradeWarning] = []
        var orderQuantity = unroundedQuantity

        if let constraints = input.constraints {
            orderQuantity = ExchangeDecimal.roundDown(unroundedQuantity, toIncrement: constraints.qtyStep)
            if orderQuantity != unroundedQuantity {
                warnings.append(.quantityRoundedDown)
            }
            if orderQuantity < constraints.minOrderQty {
                return .failure(.quantityBelowMinimum)
            }
            if orderQuantity > constraints.maxOrderQty {
                return .failure(.quantityAboveMaximum)
            }
            if constraints.minNotionalValue > 0 {
                let notional = orderQuantity * input.entryPrice
                if notional < constraints.minNotionalValue {
                    return .failure(.notionalBelowMinimum)
                }
                // SL and TP are separate orders with their own minimum quantity, calculated based on their trigger prices.
                let lowestExitPrice = min(input.stopLossPrice, input.takeProfitPrice)
                if orderQuantity * lowestExitPrice < constraints.minNotionalValue {
                    return .failure(.exitNotionalBelowMinimum)
                }
            }
        }

        let orderValue = orderQuantity * input.entryPrice
        let potentialLoss = orderQuantity * stopDistance
        let potentialProfit = orderQuantity * takeProfitDistance

        if potentialLoss < plannedRiskAmount {
            warnings.append(.estimatedRiskBelowPlanned)
        }

        if let available = input.availableBalance, available > 0, orderValue > available {
            warnings.append(.positionExceedsAvailableBalance)
        }

        return .success(
            TradeCalculationResult(
                plannedRiskAmount: plannedRiskAmount,
                riskPercentage: riskPercentage,
                stopDistance: stopDistance,
                riskReward: riskReward,
                unroundedQuantity: unroundedQuantity,
                orderQuantity: orderQuantity,
                orderValue: orderValue,
                potentialLoss: potentialLoss,
                potentialProfit: potentialProfit,
                warnings: warnings,
                isExecutable: true
            )
        )
    }

    static func parseAndCalculate(
        _ form: TradeFormInput,
        constraints: InstrumentConstraints? = nil,
        availableBalance: Decimal? = nil,
        locale: Locale = .current
    ) -> Result<TradeCalculationResult, TradeCalculationError> {
        parse(form, locale: locale).flatMap { parsed in
            var input = parsed
            input.constraints = constraints
            input.availableBalance = availableBalance
            return calculate(input)
        }
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
            form.takeProfitPrice
        ]

        if fields.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return .failure(.missingValue)
        }

        guard
            let accountBalance = decimal(from: form.accountBalance, locale: locale),
            let riskValue = decimal(from: form.riskValue, locale: locale),
            let entryPrice = decimal(from: form.entryPrice, locale: locale),
            let stopLossPrice = decimal(from: form.stopLossPrice, locale: locale),
            let takeProfitPrice = decimal(from: form.takeProfitPrice, locale: locale)
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
                takeProfitPrice: takeProfitPrice
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

        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}
