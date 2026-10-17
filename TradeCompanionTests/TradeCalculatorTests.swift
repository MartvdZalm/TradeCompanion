import Foundation
import Testing
@testable import TradeCompanion

struct TradeCalculatorTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func longPositionUsesLinearSpotFormulas() throws {
        let input = TradeCalculationInput(
            accountBalance: 10_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            riskRewardRatio: 2
        )

        let result = try TradeCalculator.calculate(input).get()

        #expect(result.riskAmount == Decimal(100))
        #expect(result.riskPercentage == Decimal(1))
        #expect(result.stopDistance == Decimal(5))
        #expect(result.positionQuantity == Decimal(20))
        #expect(result.orderValue == Decimal(2_000))
        #expect(result.takeProfitPrice == Decimal(110))
        #expect(result.potentialLoss == Decimal(100))
        #expect(result.potentialProfit == Decimal(200))
    }

    @Test func shortPositionUsesLinearSpotFormulas() throws {
        let input = TradeCalculationInput(
            accountBalance: 10_000,
            riskPercentage: 1,
            direction: .short,
            entryPrice: 100,
            stopLossPrice: 105,
            riskRewardRatio: 2
        )

        let result = try TradeCalculator.calculate(input).get()

        #expect(result.riskAmount == Decimal(100))
        #expect(result.riskPercentage == Decimal(1))
        #expect(result.stopDistance == Decimal(5))
        #expect(result.positionQuantity == Decimal(20))
        #expect(result.orderValue == Decimal(2_000))
        #expect(result.takeProfitPrice == Decimal(90))
        #expect(result.potentialLoss == Decimal(100))
        #expect(result.potentialProfit == Decimal(200))
    }

    @Test func higherRiskPercentageScalesQuantity() throws {
        let conservative = TradeCalculationInput(
            accountBalance: 5_000,
            riskPercentage: 0.5,
            direction: .long,
            entryPrice: 50,
            stopLossPrice: 49,
            riskRewardRatio: 1.5
        )
        let aggressive = TradeCalculationInput(
            accountBalance: 5_000,
            riskPercentage: 2,
            direction: .long,
            entryPrice: 50,
            stopLossPrice: 49,
            riskRewardRatio: 1.5
        )

        let conservativeResult = try TradeCalculator.calculate(conservative).get()
        let aggressiveResult = try TradeCalculator.calculate(aggressive).get()

        #expect(conservativeResult.riskAmount == Decimal(25))
        #expect(conservativeResult.positionQuantity == Decimal(25))
        #expect(conservativeResult.takeProfitPrice == dec("51.5"))
        #expect(aggressiveResult.riskAmount == Decimal(100))
        #expect(aggressiveResult.positionQuantity == Decimal(100))
        #expect(aggressiveResult.orderValue == Decimal(5_000))
        #expect(aggressiveResult.potentialProfit == Decimal(150))
    }

    @Test func fractionalPricesKeepFullPrecisionUntilDisplay() throws {
        let input = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: dec("1.2345"),
            stopLossPrice: dec("1.2300"),
            riskRewardRatio: dec("2.5")
        )

        let result = try TradeCalculator.calculate(input).get()

        #expect(result.stopDistance == dec("0.0045"))
        #expect(result.riskAmount == Decimal(10))
        #expect(result.positionQuantity == dec("10") / dec("0.0045"))
        #expect(result.takeProfitPrice == dec("1.24575"))
        #expect(result.orderValue == result.positionQuantity * input.entryPrice)
    }

    @Test func rejectsInvalidTradeConfigurations() {
        let longStopAboveEntry = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 101,
            riskRewardRatio: 2
        )
        let shortStopBelowEntry = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .short,
            entryPrice: 100,
            stopLossPrice: 99,
            riskRewardRatio: 2
        )
        let equalPrices = TradeCalculationInput(
            accountBalance: 1_000,
            riskPercentage: 1,
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 100,
            riskRewardRatio: 2
        )

        #expect(TradeCalculator.calculate(longStopAboveEntry) == .failure(.stopLossMustBeBelowEntryForLong))
        #expect(TradeCalculator.calculate(shortStopBelowEntry) == .failure(.stopLossMustBeAboveEntryForShort))
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
                    riskRewardRatio: 2
                )
            ) == .failure(.accountBalanceMustBePositive)
        )
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: -1_000,
                    riskPercentage: 1,
                    direction: .long,
                    entryPrice: 100,
                    stopLossPrice: 95,
                    riskRewardRatio: 2
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
                    riskRewardRatio: 2
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
                    riskRewardRatio: 2
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
                    riskRewardRatio: 2
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
                    riskRewardRatio: 0
                )
            ) == .failure(.riskRewardRatioMustBePositive)
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
            riskRewardRatio: "2"
        )
        let invalid = TradeFormInput(
            accountBalance: "10000",
            riskMode: .percentage,
            riskValue: "one",
            direction: .long,
            entryPrice: "100",
            stopLossPrice: "95",
            riskRewardRatio: "2"
        )
        let valid = TradeFormInput(
            accountBalance: "10000",
            riskMode: .percentage,
            riskValue: "1",
            direction: .long,
            entryPrice: "100",
            stopLossPrice: "95",
            riskRewardRatio: "2"
        )

        #expect(TradeCalculator.parseAndCalculate(empty, locale: posix) == .failure(.missingValue))
        #expect(TradeCalculator.parseAndCalculate(invalid, locale: posix) == .failure(.invalidNumber))

        let parsedResult = try TradeCalculator.parseAndCalculate(valid, locale: posix).get()
        #expect(parsedResult.positionQuantity == Decimal(20))
    }

    @Test func fixedRiskAmountProducesEquivalentPosition() throws {
        let fromPercentage = TradeCalculationInput(
            accountBalance: 10_000,
            risk: .percentage(1),
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            riskRewardRatio: 2
        )
        let fromAmount = TradeCalculationInput(
            accountBalance: 10_000,
            risk: .amount(100),
            direction: .long,
            entryPrice: 100,
            stopLossPrice: 95,
            riskRewardRatio: 2
        )

        let percentageResult = try TradeCalculator.calculate(fromPercentage).get()
        let amountResult = try TradeCalculator.calculate(fromAmount).get()

        #expect(amountResult == percentageResult)
        #expect(amountResult.riskAmount == Decimal(100))
        #expect(amountResult.riskPercentage == Decimal(1))
    }

    @Test func rejectsNonPositiveRiskAmount() {
        #expect(
            TradeCalculator.calculate(
                TradeCalculationInput(
                    accountBalance: 1_000,
                    risk: .amount(0),
                    direction: .long,
                    entryPrice: 100,
                    stopLossPrice: 95,
                    riskRewardRatio: 2
                )
            ) == .failure(.riskAmountMustBePositive)
        )
    }

    @Test func parseUsesAmountWhenRiskModeIsAmount() throws {
        let form = TradeFormInput(
            accountBalance: "8000",
            riskMode: .amount,
            riskValue: "80",
            direction: .short,
            entryPrice: "200",
            stopLossPrice: "210",
            riskRewardRatio: "1.5"
        )

        let result = try TradeCalculator.parseAndCalculate(form, locale: posix).get()
        #expect(result.riskAmount == Decimal(80))
        #expect(result.riskPercentage == Decimal(1))
        #expect(result.positionQuantity == Decimal(8))
        #expect(result.takeProfitPrice == Decimal(185))
    }

    private func dec(_ string: String) -> Decimal {
        Decimal(string: string, locale: posix)!
    }
}
