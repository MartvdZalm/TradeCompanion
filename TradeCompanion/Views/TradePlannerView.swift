import SwiftUI

struct TradePlannerView: View {
    @Bindable var model: TradePlannerViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                inputColumn
                    .frame(minWidth: 340, idealWidth: 380)
                resultColumn
                    .frame(minWidth: 380, idealWidth: 460)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Trade Planner")
        .task {
            model.refreshCredentialPresence()
            await model.loadInstrument(for: model.symbol)
        }
        .confirmationDialog(
            "Submit this order to Bybit Demo?",
            isPresented: $model.showOrderConfirmation,
            titleVisibility: .visible
        ) {
            Button("Place DEMO order", role: .destructive) {
                Task { await model.submitConfirmedOrder() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let preview = model.orderPreview {
                Text(confirmationText(preview))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TradeCompanion")
                    .font(.headline)
                Text("Trade Planner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(model.environment.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.18))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
            statusDot
            Text(model.connectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 360, alignment: .trailing)
            Button(model.isConnecting ? "Connecting…" : "Connect") {
                Task { await model.connect() }
            }
            .disabled(model.isConnecting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(model.connectionStatus.rawValue)
    }

    private var statusColor: Color {
        switch model.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .secondary
        }
    }

    private var inputColumn: some View {
        Form {
            Section("Account & Risk") {
                InputField(title: "Account balance", text: $model.accountBalance, suffix: model.quoteCurrency)
                Picker("Risk input", selection: $model.riskMode) {
                    ForEach(RiskMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if model.riskMode == .percentage {
                    InputField(title: "Risk per trade", text: $model.riskPercentage, suffix: "%")
                    ResultRow(title: "Planned risk", value: plannedRiskDisplay)
                } else {
                    InputField(title: "Risk amount", text: $model.riskAmount, suffix: model.quoteCurrency)
                }
            }

            Section("Trade Setup") {
                InputField(title: "Symbol", text: $model.symbol)
                    .onChange(of: model.symbol) {
                        model.scheduleInstrumentLoad()
                    }
                Text(model.instrumentStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Direction", selection: $model.direction) {
                    ForEach(TradeDirection.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .tint(model.direction == .long ? .green : .red)
                if model.direction == .short {
                    Text("SHORT uses spot margin: Bybit borrows the coins. Spot margin must be enabled on your account, and borrow interest is not included in the calculation.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Order type", selection: $model.orderType) {
                    ForEach(OrderEntryType.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Place SL/TP", selection: $model.protectionTiming) {
                    ForEach(ProtectionTiming.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.protectionTiming == .immediately
                     ? "SL and TP are placed right after the entry, like you do manually. If the entry never fills, they are cancelled together with it. Risk: a conditional can trigger before the entry fills (for example a TP above the market on a long)."
                     : "SL and TP are placed only after the entry has filled. Safer, but nothing is protected while the app is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                InputField(
                    title: model.orderType == .market ? "Estimate entry" : "Entry price",
                    text: $model.entryPrice
                )
                InputField(title: "Stop-loss", text: $model.stopLossPrice)
                InputField(title: "Take-profit", text: $model.takeProfitPrice)
                ResultRow(title: "Risk-to-reward", value: riskRewardDisplay)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var resultColumn: some View {
        Form {
            Section("Position & Outcome") {
                switch model.calculation {
                case .success(let result):
                    ResultRow(
                        title: "Planned risk",
                        value: TradeValueFormatting.money(result.plannedRiskAmount, currencyCode: model.quoteCurrency)
                    )
                    ResultRow(
                        title: "Position quantity",
                        value: TradeValueFormatting.decimal(result.orderQuantity, maximumFractionDigits: 8)
                    )
                    ResultRow(
                        title: "Position value",
                        value: TradeValueFormatting.money(result.orderValue, currencyCode: model.quoteCurrency),
                        footnote: "Order value in the quote currency."
                    )
                    ResultRow(
                        title: "Potential profit",
                        value: TradeValueFormatting.money(result.potentialProfit, currencyCode: model.quoteCurrency),
                        footnote: "Estimate before fees and slippage."
                    )
                    ResultRow(
                        title: "Potential loss at stop",
                        value: TradeValueFormatting.money(result.potentialLoss, currencyCode: model.quoteCurrency),
                        footnote: "Estimate before fees and slippage."
                    )
                    ResultRow(
                        title: "Risk-to-reward",
                        value: "\(TradeValueFormatting.decimal(result.riskReward, maximumFractionDigits: 4))R"
                    )
                case .failure:
                    if !model.validationMessage.isEmpty {
                        Text(model.validationMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Enter a complete trade setup to calculate size and risk.")
                            .foregroundStyle(.secondary)
                    }
                    ResultRow(title: "Planned risk", value: "—")
                    ResultRow(title: "Position quantity", value: "—")
                    ResultRow(title: "Position value", value: "—")
                    ResultRow(title: "Potential profit", value: "—")
                    ResultRow(title: "Potential loss at stop", value: "—")
                    ResultRow(title: "Risk-to-reward", value: "—")
                }
            }

            if !model.warningMessages.isEmpty {
                Section("Warnings") {
                    ForEach(model.warningMessages, id: \.self) { message in
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Order Review") {
                if let preview = model.orderPreview {
                    previewBlock(preview)
                } else if !model.validationMessage.isEmpty {
                    Text(model.validationMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("Complete a valid setup and connect to Bybit Demo before submitting.")
                        .foregroundStyle(.secondary)
                }

                Button(model.isSubmitting ? "Submitting…" : "Review DEMO order") {
                    model.showOrderConfirmation = true
                }
                .disabled(!model.canSubmit)
                .buttonStyle(.borderedProminent)
                .tint(model.direction == .long ? .green : .red)

                if let reason = model.submitBlockReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !model.orderStatusMessage.isEmpty {
                    Text(model.orderStatusMessage)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if !model.protectionStatusMessage.isEmpty {
                    Text(model.protectionStatusMessage)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if model.isMonitoring {
                    HStack {
                        if model.canCancelEntry {
                            Button("Cancel entry") {
                                Task { await model.cancelOpenEntry() }
                            }
                        }
                        Button("Stop monitoring") {
                            model.stopMonitoring()
                        }
                    }
                    Text("Monitoring only runs while this app is open. If you close it, stop-loss and take-profit are not placed or managed.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text("Spot pairs on Bybit EU (shorts via spot margin). SL and TP are placed as separate conditional orders after the entry fills. Estimates ignore fees, interest and slippage. Orders are submitted only after confirmation, and only to Bybit Demo. Live trading is disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func previewBlock(_ preview: OrderPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labeled("Environment", preview.environment)
            labeled("Symbol", "\(preview.symbol) · \(preview.direction.rawValue)")
            labeled("Mode", preview.direction == .short ? "Spot margin (borrow)" : "Spot")
            labeled("Order type", preview.orderType.rawValue)
            labeled("Entry", preview.entryDescription)
            labeled("Quantity", preview.quantity)
            labeled("Est. value", preview.orderValue)
            labeled("Stop-loss", preview.stopLoss)
            labeled("Take-profit", preview.takeProfit)
            labeled("Est. max loss", preview.plannedLoss)
            labeled("R:R", "\(preview.riskReward)R")
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .textSelection(.enabled)
        }
    }

    private var plannedRiskDisplay: String {
        if case .success(let result) = model.calculation {
            return TradeValueFormatting.money(result.plannedRiskAmount, currencyCode: model.quoteCurrency)
        }
        if let balance = TradeCalculator.decimal(from: model.accountBalance, locale: .current),
           let percent = TradeCalculator.decimal(from: model.riskPercentage, locale: .current),
           balance > 0, percent > 0 {
            return TradeValueFormatting.money(balance * percent / 100, currencyCode: model.quoteCurrency)
        }
        return "—"
    }

    private var riskRewardDisplay: String {
        if case .success(let result) = model.calculation {
            return "\(TradeValueFormatting.decimal(result.riskReward, maximumFractionDigits: 4))R"
        }
        return "—"
    }

    private func confirmationText(_ preview: OrderPreview) -> String {
        """
        \(preview.environment) · \(preview.symbol) \(preview.direction.rawValue)\(preview.direction == .short ? " (spot margin)" : "")
        \(preview.orderType.rawValue) \(preview.entryDescription)
        Qty \(preview.quantity) · Value \(preview.orderValue)
        SL \(preview.stopLoss) · TP \(preview.takeProfit) (\(model.protectionTiming.rawValue.lowercased()))
        Est. loss \(preview.plannedLoss) · R:R \(preview.riskReward)
        """
    }
}
