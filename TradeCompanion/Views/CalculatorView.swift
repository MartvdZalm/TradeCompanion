import SwiftUI

struct CalculatorView: View {
    @State private var accountBalance = ""
    @State private var accountCurrency = "USD"
    @State private var riskMode: RiskMode = .percentage
    @State private var riskPercentage = "1"
    @State private var riskAmount = ""
    @State private var direction: TradeDirection = .long
    @State private var entryPrice = ""
    @State private var stopLossPrice = ""
    @State private var riskRewardRatio = "2"

    private let currencies = ["USD", "EUR", "GBP", "CHF", "JPY", "CAD", "AUD"]

    private var formInput: TradeFormInput {
        TradeFormInput(
            accountBalance: accountBalance,
            riskMode: riskMode,
            riskValue: riskMode == .percentage ? riskPercentage : riskAmount,
            direction: direction,
            entryPrice: entryPrice,
            stopLossPrice: stopLossPrice,
            riskRewardRatio: riskRewardRatio
        )
    }

    private var calculation: Result<TradeCalculationResult, TradeCalculationError> {
        TradeCalculator.parseAndCalculate(formInput)
    }

    var body: some View {
        HSplitView {
            inputPanel
                .frame(minWidth: 280, idealWidth: 340)
            resultPanel
                .frame(minWidth: 280, idealWidth: 360)
        }
        .navigationTitle("Trade Calculator")
        .padding(16)
    }

    private var inputPanel: some View {
        Form {
            Section("Account") {
                InputField(title: "Account balance", text: $accountBalance, suffix: accountCurrency)
                Picker("Account currency", selection: $accountCurrency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                Picker("Risk input", selection: $riskMode) {
                    ForEach(RiskMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if riskMode == .percentage {
                    InputField(title: "Risk per trade", text: $riskPercentage, suffix: "%")
                } else {
                    InputField(title: "Risk per trade", text: $riskAmount, suffix: accountCurrency)
                }
            }

            Section("Trade") {
                Picker("Direction", selection: $direction) {
                    ForEach(TradeDirection.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                InputField(title: "Entry price", text: $entryPrice)
                InputField(title: "Stop-loss price", text: $stopLossPrice)
                InputField(title: "Risk-to-reward", text: $riskRewardRatio, suffix: "R")
            }
        }
        .formStyle(.grouped)
    }

    private var resultPanel: some View {
        Form {
            Section("Estimate") {
                switch calculation {
                case .success(let result):
                    ResultRow(
                        title: "Monetary risk",
                        value: TradeValueFormatting.money(result.riskAmount, currencyCode: accountCurrency)
                    )
                    ResultRow(
                        title: "Risk percentage",
                        value: TradeValueFormatting.percent(result.riskPercentage)
                    )
                    ResultRow(
                        title: "Stop-loss distance",
                        value: TradeValueFormatting.decimal(result.stopDistance, maximumFractionDigits: 8)
                    )
                    ResultRow(
                        title: "Position quantity",
                        value: TradeValueFormatting.decimal(result.positionQuantity, maximumFractionDigits: 8)
                    )
                    ResultRow(
                        title: "Order value",
                        value: TradeValueFormatting.money(result.orderValue, currencyCode: accountCurrency),
                        footnote: "Not required margin. Leverage is not assumed."
                    )
                    ResultRow(
                        title: "Take-profit price",
                        value: TradeValueFormatting.decimal(result.takeProfitPrice, maximumFractionDigits: 8)
                    )
                    ResultRow(
                        title: "Potential loss",
                        value: TradeValueFormatting.money(result.potentialLoss, currencyCode: accountCurrency),
                        footnote: "Before fees and slippage."
                    )
                    ResultRow(
                        title: "Potential profit",
                        value: TradeValueFormatting.money(result.potentialProfit, currencyCode: accountCurrency),
                        footnote: "Before fees and slippage."
                    )
                case .failure(let error):
                    Text(error.userMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    ResultRow(title: "Monetary risk", value: "—")
                    ResultRow(title: "Risk percentage", value: "—")
                    ResultRow(title: "Stop-loss distance", value: "—")
                    ResultRow(title: "Position quantity", value: "—")
                    ResultRow(title: "Order value", value: "—")
                    ResultRow(title: "Take-profit price", value: "—")
                    ResultRow(title: "Potential loss", value: "—")
                    ResultRow(title: "Potential profit", value: "—")
                }
            }

            Section {
                Text("Linear spot-style estimate. Fees, slippage, contract specs, and exchange rules can change actual results. Planned risk is not the same as realized loss.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    CalculatorView()
        .frame(width: 760, height: 560)
}
