import Foundation
import Testing
@testable import TradeCompanion

struct TradeCalculatorTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func riskAmountFromBalanceAndPercentage() throws {
        let input = TradeCalculationInput(
            accountBalance: 5_600,
            riskPercentage: Decimal(string: "0.5", locale: posix)!,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 99,
            takeProfitPrice: 102
        )

        let result = try TradeCalculator.calculate(input).get()
        #expect(result.plannedRiskAmount == Decimal(28))
        #expect(result.riskPercentage == Decimal(string: "0.5", locale: posix)!)
        #expect(result.orderQuantity == Decimal(28))
        #expect(result.riskReward == Decimal(2))
    }

    @Test func longPositionUsesLinearSpotFormulas() throws {
        let input = TradeCalculationInput(
            accountBalance: 10_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            takeProfitPrice: 110
        )

        let result = try TradeCalculator.calculate(input).get()

        #expect(result.plannedRiskAmount == Decimal(100))
        #expect(result.stopDistance == Decimal(5))
        #expect(result.orderQuantity == Decimal(20))
        #expect(result.orderValue == Decimal(2_000))
        #expect(result.potentialLoss == Decimal(100))
        #expect(result.potentialProfit == Decimal(200))
        #expect(result.riskReward == Decimal(2))
        #expect(result.isExecutable)
    }

    @Test func shortPositionUsesLinearSpotFormulas() throws {
        let input = TradeCalculationInput(
            accountBalance: 10_000,
            riskPercentage: 1,
            direction: .short,
            entryPrice: 100,
            stopLossPrice: 105,
            takeProfitPrice: 90
        )

        let result = try TradeCalculator.calculate(input).get()

        #expect(result.orderQuantity == Decimal(20))
        #expect(result.orderValue == Decimal(2_000))
        #expect(result.potentialProfit == Decimal(200))
        #expect(result.riskReward == Decimal(2))
    }

    @Test func rejectsInvalidTradeConfigurations() {
        let longStopAboveEntry = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 101,
            takeProfitPrice: 110
        )
        let longTakeProfitBelowEntry = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            takeProfitPrice: 90
        )
        let shortStopBelowEntry = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .short,
            entryPrice: 100,
            stopLossPrice: 99,
            takeProfitPrice: 90
        )
        let shortTakeProfitAboveEntry = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .short,
            entryPrice: 100,
            stopLossPrice: 105,
            takeProfitPrice: 110
        )
        let equalPrices = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 100,
            takeProfitPrice: 110
        )

        #expect(TradeCalculator.calculate(longStopAboveEntry) == .failure(.stopLossMustBeBelowEntryForLong))
        #expect(TradeCalculator.calculate(longTakeProfitBelowEntry) == .failure(.takeProfitMustBeAboveEntryForLong))
        #expect(TradeCalculator.calculate(shortStopBelowEntry) == .failure(.stopLossMustBeAboveEntryForShort))
        #expect(TradeCalculator.calculate(shortTakeProfitAboveEntry) == .failure(.takeProfitMustBeBelowEntryForShort))
        #expect(TradeCalculator.calculate(equalPrices) == .failure(.stopLossMustDifferFromEntry))
    }

    @Test func rejectsNonPositiveAndZeroInputs() {
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: 0,
                    riskPercentage: 1,
                    direction: .long,
                    entryPrice: 100,
                    stopLossPrice: 95,
                    takeProfitPrice: 110
                )
            ) == .failure(.accountBalanceMustBePositive)
        )
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: 1_000,
                    riskPercentage: 0,
                    direction: .long,
                    entryPrice: 100,
                    stopLossPrice: 95,
                    takeProfitPrice: 110
                )
            ) == .failure(.riskPercentageMustBePositive)
        )
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: 1_000,
                    riskPercentage: 1,
                    direction: .long,
                    entryPrice: 0,
                    stopLossPrice: 95,
                    takeProfitPrice: 110
                )
            ) == .failure(.entryPriceMustBePositive)
        )
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: 1_000,
                    riskPercentage: 1,
                    direction: .long,
                    entryPrice: 100,
                    stopLossPrice: -5,
                    takeProfitPrice: 110
                )
            ) == .failure(.stopLossPriceMustBePositive)
        )
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: 1_000,
                    riskPercentage: 1,
                    direction: .long,
                    entryPrice: 100,
                    stopLossPrice: 95,
                    takeProfitPrice: 0
                )
            ) == .failure(.takeProfitPriceMustBePositive)
        )
    }

    @Test func parseRejectsEmptyAndInvalidFields() throws {
        let empty = TradeFormInput(
            accountBalance: " ",
            riskMode: .percentage,
            riskValue: "1",
            direction: .long,
            entryPrice: "100",
            stopLossPrice: "95",
            takeProfitPrice: "110"
        )
        let invalid = TradeFormInput(
            accountBalance: "10000",
            riskMode: .percentage,
            riskValue: "one",
            direction: .long,
            entryPrice: "100",
            stopLossPrice: "95",
            takeProfitPrice: "110"
        )
        let valid = TradeFormInput(
            accountBalance: "10000",
            riskMode: .percentage,
            riskValue: "1",
            direction: .long,
            entryPrice: "100",
            stopLossPrice: "95",
            takeProfitPrice: "110"
        )

        #expect(TradeCalculator.parseAndCalculate(empty, locale: posix) == .failure(.missingValue))
        #expect(TradeCalculator.parseAndCalculate(invalid, locale: posix) == .failure(.invalidNumber))

        let parsedResult = try TradeCalculator.parseAndCalculate(valid, locale: posix).get()
        #expect(parsedResult.orderQuantity == Decimal(20))
    }

    @Test func fixedRiskAmountProducesEquivalentPosition() throws {
        let fromPercentage = TradeCalculationInput(
            accountBalance: 10_000,
            risk: .percentage(1),
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            takeProfitPrice: 110
        )
        let fromAmount = TradeCalculationInput(
            accountBalance: 10_000,
            risk: .amount(100),
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            takeProfitPrice: 110
        )

        let percentageResult = try TradeCalculator.calculate(fromPercentage).get()
        let amountResult = try TradeCalculator.calculate(fromAmount).get()

        #expect(amountResult.orderQuantity == percentageResult.orderQuantity)
        #expect(amountResult.plannedRiskAmount == Decimal(100))
    }

    @Test func roundsQuantityDownToExchangeIncrement() throws {
        let constraints = linearConstraints(qtyStep: "0.001", minOrderQty: "0.001", minNotional: "5")
        let input = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: dec("100.00"),
            stopLossPrice: dec("97.00"),
            takeProfitPrice: dec("106.00"),
            constraints: constraints
        )

        let result = try TradeCalculator.calculate(input).get()
        #expect(result.unroundedQuantity == dec("10") / dec("3"))
        #expect(result.orderQuantity == dec("3.333"))
        #expect(result.warnings.contains(.quantityRoundedDown))
        #expect(result.warnings.contains(.estimatedRiskBelowPlanned))
        #expect(result.potentialLoss < result.plannedRiskAmount)
    }

    @Test func rejectsQuantityBelowExchangeMinimum() {
        let constraints = linearConstraints(qtyStep: "0.1", minOrderQty: "0.1", minNotional: "5")
        let input = TradeCalculationInput(
            accountBalance: 10,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 98,
            takeProfitPrice: 104,
            constraints: constraints
        )

        #expect(TradeCalculator.calculate(input) == .failure(.quantityBelowMinimum))
    }

    @Test func rejectsUnsupportedInverseContract() {
        var constraints = linearConstraints(qtyStep: "1", minOrderQty: "1", minNotional: "1")
        constraints.contractType = "InversePerpetual"
        constraints.quoteCoin = "USD"
        constraints.settleCoin = "BTC"
        let input = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            takeProfitPrice: 110,
            constraints: constraints
        )
        #expect(TradeCalculator.calculate(input) == .failure(.unsupportedContractType))
    }

    @Test func warnsWhenNotionalExceedsAvailableBalance() throws {
        let input = TradeCalculationInput(
            accountBalance: 10_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            takeProfitPrice: 110,
            availableBalance: 500
        )
        let result = try TradeCalculator.calculate(input).get()
        #expect(result.orderValue == Decimal(2_000))
        #expect(result.warnings.contains(.positionExceedsAvailableBalance))
    }

    @Test func rejectsNotionalBelowMinimum() {
        let constraints = linearConstraints(qtyStep: "0.001", minOrderQty: "0.001", minNotional: "5000")
        let input = TradeCalculationInput(
            accountBalance: 100,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 99,
            takeProfitPrice: 102,
            constraints: constraints
        )
        #expect(TradeCalculator.calculate(input) == .failure(.notionalBelowMinimum))
    }

    private func linearConstraints(qtyStep: String, minOrderQty: String, minNotional: String) -> InstrumentConstraints {
        InstrumentConstraints(
            symbol: "BTCUSDT",
            contractType: "LinearPerpetual",
            status: "Trading",
            baseCoin: "BTC",
            quoteCoin: "USDT",
            settleCoin: "USDT",
            tickSize: dec("0.1"),
            qtyStep: dec(qtyStep),
            minOrderQty: dec(minOrderQty),
            maxOrderQty: dec("100"),
            maxMarketOrderQty: dec("100"),
            minNotionalValue: dec(minNotional)
        )
    }

    private func dec(_ string: String) -> Decimal {
        Decimal(string: string, locale: posix)!
    }
}
