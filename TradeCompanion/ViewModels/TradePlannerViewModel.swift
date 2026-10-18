import Foundation
import Observation

@Observable
final class TradePlannerViewModel {
    var accountBalance = ""
    var riskMode: RiskMode = .percentage
    var riskPercentage = "0.5"
    var riskAmount = ""
    var symbol = "SOLUSDC"
    var direction: TradeDirection = .long
    var orderType: OrderEntryType = .limit
    var protectionTiming: ProtectionTiming = .immediately
    var entryPrice = ""
    var stopLossPrice = ""
    var takeProfitPrice = ""

    var instrument: InstrumentConstraints?
    var instrumentStatus = "Enter a spot symbol (for example SOLUSDC) to load exchange rules."
    var wallet: BybitWalletSnapshot?
    var connectionStatus: ConnectionStatus = .disconnected
    var connectionDetail = "Disconnected. The calculator still works without API keys."
    var orderStatusMessage = ""
    var protectionStatusMessage = ""
    var lastOrder: BybitOrderRecord?
    var entryOrder: BybitPlacedOrder?
    var stopLossOrder: BybitPlacedOrder?
    var takeProfitOrder: BybitPlacedOrder?
    var isConnecting = false
    var isLoadingInstrument = false
    var isSubmitting = false
    var isMonitoring = false
    var showOrderConfirmation = false
    var credentialsPresent = false

    /// Spot taker/maker fee zoals de demo die toonde (0,25%). Wordt gebruikt om de
    /// hoeveelheid van SL/TP aan te passen, omdat de fee van de coins afgaat.
    private static let spotFeeRate = Decimal(string: "0.0025")!

    private var instrumentTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var activeSymbol: String?
    private let client: BybitAPIClient
    private let keychain: KeychainStore

    init(
        client: BybitAPIClient = BybitAPIClient(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.client = client
        self.keychain = keychain

        credentialsPresent = keychain.hasDemoCredentials()
    }

    var environment: BybitEnvironment { .demo }

    var quoteCurrency: String {
        instrument?.quoteCoin ?? "USDC"
    }

    var formInput: TradeFormInput {
        TradeFormInput(
            accountBalance: accountBalance,
            riskMode: riskMode,
            riskValue: riskMode == .percentage ? riskPercentage : riskAmount,
            direction: direction,
            entryPrice: entryPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice
        )
    }

    /// Without a wallet balance endpoint, we cannot determine the available balance.
    /// For a spot long, the position cannot exceed the available balance, so we use that.
    private var effectiveAvailableBalance: Decimal? {
        if let available = wallet?.totalAvailableBalance { return available }
        if direction == .long {
            return TradeCalculator.decimal(from: accountBalance, locale: .current)
        }
        return nil
    }

    var calculation: Result<TradeCalculationResult, TradeCalculationError> {
        TradeCalculator.parseAndCalculate(
            formInput,
            constraints: instrument,
            availableBalance: effectiveAvailableBalance,
            locale: .current
        )
    }

    var validationMessage: String {
        switch calculation {
        case .success:
            return ""
        case .failure(let error):
            return error.userMessage
        }
    }

    var warningMessages: [String] {
        guard case .success(let result) = calculation else { return [] }
        return result.warnings.map { warning in
            switch warning {
            case .quantityRoundedDown:
                return "Quantity was rounded down to the exchange increment so planned risk is not increased."
            case .estimatedRiskBelowPlanned:
                return "Estimated stop-loss loss is below the planned risk amount because quantity was rounded down."
            case .positionExceedsAvailableBalance:
                return direction == .long
                    ? "Estimated order value exceeds your account balance. A spot long cannot be filled without leverage."
                    : "Estimated order value exceeds the available balance."
            }
        }
    }

    var submitBlockReason: String? {
        if isSubmitting { return "An order is being submitted…" }
        if isMonitoring { return "A trade is being monitored. Cancel the entry or stop monitoring first." }
        if !credentialsPresent { return "Add Bybit Demo API keys in Settings." }
        if connectionStatus != .connected { return "Connect to Bybit Demo first." }
        guard let instrument else { return "Instrument rules are not loaded. \(instrumentStatus)" }
        if !instrument.supportsPlannerFormulas {
            return "\(instrument.symbol) is not tradable as spot right now (status: \(instrument.status))."
        }
        switch calculation {
        case .failure(let error):
            let message = error.userMessage
            return message.isEmpty ? "Complete the trade setup." : message
        case .success(let result):
            if !result.isExecutable || result.orderQuantity <= 0 {
                return "The calculated quantity is zero."
            }
        }
        return nil
    }

    var canSubmit: Bool { submitBlockReason == nil }

    var canCancelEntry: Bool {
        guard isMonitoring, entryOrder != nil else { return false }
        guard let status = lastOrder?.orderStatus.lowercased() else { return true }
        return ["new", "partiallyfilled"].contains(status)
    }

    var orderPreview: OrderPreview? {
        guard case .success(let result) = calculation, let instrument else { return nil }
        let entryDescription: String
        switch orderType {
        case .limit:
            entryDescription = ExchangeDecimal.format(parsedEntryPrice ?? 0, increment: instrument.tickSize)
        case .market:
            entryDescription = "Market (estimate \(entryPrice))"
        }
        return OrderPreview(
            environment: environment.displayName,
            symbol: instrument.symbol,
            direction: direction,
            orderType: orderType,
            entryDescription: entryDescription,
            quantity: ExchangeDecimal.format(result.orderQuantity, increment: instrument.qtyStep),
            orderValue: TradeValueFormatting.money(result.orderValue, currencyCode: quoteCurrency),
            stopLoss: ExchangeDecimal.format(parsedStopLoss ?? 0, increment: instrument.tickSize),
            takeProfit: ExchangeDecimal.format(parsedTakeProfit ?? 0, increment: instrument.tickSize),
            plannedLoss: TradeValueFormatting.money(result.potentialLoss, currencyCode: quoteCurrency),
            riskReward: TradeValueFormatting.decimal(result.riskReward, maximumFractionDigits: 4)
        )
    }

    func refreshCredentialPresence() {
        credentialsPresent = keychain.hasDemoCredentials()
        if !credentialsPresent {
            connectionStatus = .disconnected
            connectionDetail = "Disconnected. Add Bybit Demo API keys in Settings to connect."
            wallet = nil
        }
    }

    func scheduleInstrumentLoad() {
        instrumentTask?.cancel()
        let requested = symbol
        instrumentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.loadInstrument(for: requested)
        }
    }

    func connect() async {
        refreshCredentialPresence()
        guard let credentials = keychain.loadDemoCredentials() else {
            connectionStatus = .disconnected
            connectionDetail = "Disconnected. Add Bybit Demo API keys in Settings."
            return
        }
        isConnecting = true
        connectionStatus = .connecting
        connectionDetail = "Connecting to Bybit Demo…"
        defer { isConnecting = false }
        do {
            try await client.checkConnection(credentials: credentials)
            wallet = nil
            connectionStatus = .connected
            connectionDetail = "Connected to Bybit Demo."
            await loadInstrument(for: symbol)
        } catch let error as BybitAPIError {
            connectionStatus = .disconnected
            connectionDetail = error.userMessage
            wallet = nil
        } catch {
            connectionStatus = .disconnected
            connectionDetail = error.localizedDescription
            wallet = nil
        }
    }

    func loadInstrument(for rawSymbol: String) async {
        let trimmed = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            instrument = nil
            instrumentStatus = "Enter a spot symbol (for example SOLUSDC) to load exchange rules."
            return
        }
        isLoadingInstrument = true
        defer { isLoadingInstrument = false }
        do {
            let spec = try await client.instrument(symbol: trimmed, credentials: nil)
            guard !Task.isCancelled else { return }
            instrument = spec
            if spec.supportsPlannerFormulas {
                instrumentStatus = "\(spec.symbol) · spot · tick \(ExchangeDecimal.formatExact(spec.tickSize)) · qty step \(ExchangeDecimal.formatExact(spec.qtyStep)) · min order \(ExchangeDecimal.formatExact(spec.minNotionalValue)) \(spec.quoteCoin)"
            } else {
                instrumentStatus = "\(spec.symbol) loaded, but its status is \(spec.status), so it cannot be traded right now."
            }
        } catch let error as BybitAPIError {
            instrument = nil
            instrumentStatus = error.userMessage
        } catch {
            instrument = nil
            instrumentStatus = error.localizedDescription
        }
    }

    func submitConfirmedOrder() async {
        if let reason = submitBlockReason {
            orderStatusMessage = reason
            return
        }
        guard let preview = orderPreview, let instrument else {
            orderStatusMessage = "The order preview is not available. Check the trade setup."
            return
        }
        guard let credentials = keychain.loadDemoCredentials() else {
            orderStatusMessage = BybitAPIError.missingCredentials.userMessage
            return
        }
        isSubmitting = true
        lastOrder = nil
        entryOrder = nil
        stopLossOrder = nil
        takeProfitOrder = nil
        protectionStatusMessage = ""
        orderStatusMessage = "Submitting to Bybit Demo…"
        defer { isSubmitting = false }

        let linkId = "tc-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))"
        do {
            // Step 1: Entry only. SL and TP are handled by separate conditionals.
            let placed = try await client.placeOrder(
                credentials: credentials,
                symbol: instrument.symbol,
                direction: direction,
                orderType: orderType,
                quantity: preview.quantity,
                price: orderType == .limit ? preview.entryDescription : nil,
                orderLinkId: String(linkId)
            )
            entryOrder = placed
            activeSymbol = instrument.symbol
            orderStatusMessage = "Bybit accepted order \(placed.orderId). Waiting for the entry to fill…"

            startMonitoring(
                credentials: credentials,
                symbol: instrument.symbol,
                direction: direction,
                qtyStep: instrument.qtyStep,
                timing: protectionTiming,
                plannedQuantity: preview.quantity,
                entry: placed,
                stopLoss: preview.stopLoss,
                takeProfit: preview.takeProfit
            )
        } catch let error as BybitAPIError {
            orderStatusMessage = error.userMessage
        } catch {
            orderStatusMessage = error.localizedDescription
        }
    }

    /// Cancels the pending entry order on Bybit. Tracking stops automatically once Bybit
    /// reports "Cancelled". If the order was partially filled, SL and TP are placed for the filled portion.
    func cancelOpenEntry() async {
        guard let entry = entryOrder, let symbol = activeSymbol,
              let credentials = keychain.loadDemoCredentials() else { return }
        do {
            try await client.cancelOrder(
                credentials: credentials, symbol: symbol,
                orderId: entry.orderId, isConditional: false)
            orderStatusMessage = "Cancel requested for entry \(entry.orderId)."
        } catch let error as BybitAPIError {
            orderStatusMessage = "Could not cancel the entry: \(error.userMessage)"
        } catch {
            orderStatusMessage = "Could not cancel the entry: \(error.localizedDescription)"
        }
    }

    /// Stops tracking the order in the app only. No orders are cancelled on Bybit.
    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        protectionStatusMessage += " Monitoring stopped. Orders on Bybit were not changed."
    }

    private enum ProtectionEvent {
        case none
        case fired
        case bothEnded
    }

    private func startMonitoring(
        credentials: BybitCredentials,
        symbol: String,
        direction: TradeDirection,
        qtyStep: Decimal,
        timing: ProtectionTiming,
        plannedQuantity: String,
        entry: BybitPlacedOrder,
        stopLoss: String,
        takeProfit: String
    ) {
        monitorTask?.cancel()
        isMonitoring = true
        monitorTask = Task { [weak self] in
            await self?.monitorAndProtect(
                credentials: credentials,
                symbol: symbol,
                direction: direction,
                qtyStep: qtyStep,
                timing: timing,
                plannedQuantity: plannedQuantity,
                entry: entry,
                stopLoss: stopLoss,
                takeProfit: takeProfit
            )
            self?.isMonitoring = false
        }
    }

    private func monitorAndProtect(
        credentials: BybitCredentials,
        symbol: String,
        direction: TradeDirection,
        qtyStep: Decimal,
        timing: ProtectionTiming,
        plannedQuantity: String,
        entry: BybitPlacedOrder,
        stopLoss: String,
        takeProfit: String
    ) async {
        var protection: (sl: BybitPlacedOrder, tp: BybitPlacedOrder)?

        // Direct: Place SL and TP immediately after the entry.
        if timing == .immediately {
            let qty = Self.exitQuantity(filled: plannedQuantity, direction: direction, step: qtyStep)
            do {
                let placed = try await placeProtection(
                    credentials: credentials, symbol: symbol, direction: direction,
                    quantity: qty, stopLoss: stopLoss, takeProfit: takeProfit,
                    keepStopLossOnTakeProfitFailure: false)
                protection = placed
                protectionStatusMessage = "Stop-loss \(placed.sl.orderId) and take-profit \(placed.tp.orderId) placed (qty \(qty)). Waiting for the entry to fill…"
            } catch {
                protectionStatusMessage = "Stop-loss/take-profit could not be placed: \(Self.describe(error)) The entry is being cancelled."
                try? await client.cancelOrder(
                    credentials: credentials, symbol: symbol,
                    orderId: entry.orderId, isConditional: false)
                return
            }
        }

        // Phase 1: Wait for the entry order to be filled.
        var filledQty = ""
        waitForFill: while !Task.isCancelled {
            if let active = protection {
                switch await checkProtection(credentials: credentials, symbol: symbol, sl: active.sl, tp: active.tp) {
                case .fired:
                    try? await client.cancelOrder(
                        credentials: credentials, symbol: symbol,
                        orderId: entry.orderId, isConditional: false)
                    orderStatusMessage = "A conditional order triggered before the entry filled. The entry was cancelled."
                    return
                case .bothEnded:
                    try? await client.cancelOrder(
                        credentials: credentials, symbol: symbol,
                        orderId: entry.orderId, isConditional: false)
                    protectionStatusMessage = "Both conditional orders ended before the entry filled. The entry was cancelled."
                    return
                case .none:
                    break
                }
            }

            do {
                let record = try await client.order(
                    credentials: credentials,
                    symbol: symbol,
                    orderId: entry.orderId,
                    orderLinkId: nil
                )
                lastOrder = record
                let status = record.orderStatus.lowercased()
                let filled = Self.decimal(record.cumExecQty)

                switch status {
                case "filled":
                    filledQty = record.cumExecQty
                    orderStatusMessage = "Entry \(record.orderId) filled (\(record.cumExecQty))."
                    break waitForFill
                case "partiallyfilledcanceled", "cancelled", "deactivated", "rejected":
                    if filled > 0 {
                        filledQty = record.cumExecQty
                        orderStatusMessage = "Entry ended as \(record.orderStatus) with \(record.cumExecQty) filled."
                        break waitForFill
                    }
                    var text = "Entry \(record.orderId) ended as \(record.orderStatus) without a fill."
                    if status == "rejected" { text += " Reject reason: \(record.rejectReason)." }
                    orderStatusMessage = text
                    if let active = protection {
                        await cancelProtection(credentials: credentials, symbol: symbol, protection: active)
                        protectionStatusMessage = "The entry ended without a fill, so stop-loss and take-profit were cancelled."
                    }
                    return
                case "partiallyfilled":
                    orderStatusMessage = "Entry partially filled: \(record.cumExecQty) filled, \(record.leavesQty) remaining."
                default:
                    orderStatusMessage = "Entry \(record.orderId) status: \(record.orderStatus). Waiting for fill…"
                }
            } catch let error as BybitAPIError {
                orderStatusMessage = "Could not read entry status yet: \(error.userMessage)"
            } catch {
                orderStatusMessage = "Could not read entry status yet: \(error.localizedDescription)"
            }
            try? await Task.sleep(for: .seconds(3))
        }
        guard !Task.isCancelled else { return }

        // Phase 2: Place SL and TP after the entry is filled (only in "after fill" mode).
        if protection == nil {
            let qty = Self.exitQuantity(filled: filledQty, direction: direction, step: qtyStep)
            do {
                let placed = try await placeProtection(
                    credentials: credentials, symbol: symbol, direction: direction,
                    quantity: qty, stopLoss: stopLoss, takeProfit: takeProfit,
                    keepStopLossOnTakeProfitFailure: true)
                protection = placed
                protectionStatusMessage = "Stop-loss \(placed.sl.orderId) and take-profit \(placed.tp.orderId) are placed (qty \(qty)). Watching for a trigger…"
            } catch {
                if let slOrder = stopLossOrder {
                    protectionStatusMessage = "Stop-loss \(slOrder.orderId) is active, but take-profit failed: \(Self.describe(error))"
                } else {
                    protectionStatusMessage = "Stop-loss could not be placed: \(Self.describe(error)) The position is NOT protected."
                }
                return
            }
        } else if let active = protection {
            protectionStatusMessage = "Entry filled. Stop-loss \(active.sl.orderId) and take-profit \(active.tp.orderId) are active. Watching for a trigger…"
        }

        // Phase 3: Cancel the other order when one of them is triggered.
        guard let active = protection else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            switch await checkProtection(credentials: credentials, symbol: symbol, sl: active.sl, tp: active.tp) {
            case .fired:
                return
            case .bothEnded:
                protectionStatusMessage = "Both conditional orders ended without triggering (cancelled elsewhere?)."
                return
            case .none:
                continue
            }
        }
    }

    /// Places the SL first, followed by the TP. If the TP order fails and
    /// `keepStopLossOnTakeProfitFailure` is false, the SL is cancelled to avoid
    /// leaving the position in a partially configured state.
    private func placeProtection(
        credentials: BybitCredentials,
        symbol: String,
        direction: TradeDirection,
        quantity: String,
        stopLoss: String,
        takeProfit: String,
        keepStopLossOnTakeProfitFailure: Bool
    ) async throws -> (sl: BybitPlacedOrder, tp: BybitPlacedOrder) {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let sl = try await client.placeConditional(
            credentials: credentials, symbol: symbol, direction: direction,
            kind: .stopLoss, quantity: quantity, triggerPrice: stopLoss,
            orderLinkId: "sl-\(id)")
        stopLossOrder = sl
        do {
            let tp = try await client.placeConditional(
                credentials: credentials, symbol: symbol, direction: direction,
                kind: .takeProfit, quantity: quantity, triggerPrice: takeProfit,
                orderLinkId: "tp-\(id)")
            takeProfitOrder = tp
            return (sl, tp)
        } catch {
            if !keepStopLossOnTakeProfitFailure {
                try? await client.cancelOrder(
                    credentials: credentials, symbol: symbol,
                    orderId: sl.orderId, isConditional: true)
                stopLossOrder = nil
            }
            throw error
        }
    }

    /// Polls the SL and TP orders. When one is triggered, the other is cancelled.
    private func checkProtection(
        credentials: BybitCredentials,
        symbol: String,
        sl: BybitPlacedOrder,
        tp: BybitPlacedOrder
    ) async -> ProtectionEvent {
        let slRecord = try? await client.order(
            credentials: credentials, symbol: symbol,
            orderId: sl.orderId, orderLinkId: nil, isConditional: true)
        let tpRecord = try? await client.order(
            credentials: credentials, symbol: symbol,
            orderId: tp.orderId, orderLinkId: nil, isConditional: true)

        if let record = slRecord, Self.hasFired(record.orderStatus) {
            await cancelOther(credentials: credentials, symbol: symbol, order: tp,
                              firedName: "Stop-loss", otherName: "take-profit")
            return .fired
        }
        if let record = tpRecord, Self.hasFired(record.orderStatus) {
            await cancelOther(credentials: credentials, symbol: symbol, order: sl,
                              firedName: "Take-profit", otherName: "stop-loss")
            return .fired
        }

        let slEnded = slRecord.map { Self.hasEnded($0.orderStatus) } ?? false
        let tpEnded = tpRecord.map { Self.hasEnded($0.orderStatus) } ?? false
        return (slEnded && tpEnded) ? .bothEnded : .none
    }

    private func cancelProtection(
        credentials: BybitCredentials,
        symbol: String,
        protection: (sl: BybitPlacedOrder, tp: BybitPlacedOrder)
    ) async {
        try? await client.cancelOrder(
            credentials: credentials, symbol: symbol,
            orderId: protection.sl.orderId, isConditional: true)
        try? await client.cancelOrder(
            credentials: credentials, symbol: symbol,
            orderId: protection.tp.orderId, isConditional: true)
    }

    private func cancelOther(
        credentials: BybitCredentials,
        symbol: String,
        order: BybitPlacedOrder,
        firedName: String,
        otherName: String
    ) async {
        do {
            try await client.cancelOrder(
                credentials: credentials, symbol: symbol,
                orderId: order.orderId, isConditional: true)
            protectionStatusMessage = "\(firedName) triggered. The \(otherName) was cancelled."
        } catch {
            protectionStatusMessage = "\(firedName) triggered, but cancelling the \(otherName) failed: \(Self.describe(error)) Cancel it manually."
        }
    }

    /// Quantity for SL/TP.
    /// Long: For a spot buy, the fee is deducted from the purchased coins, so you receive slightly less than the filled quantity.
    ///       We therefore sell the filled quantity minus the fee, rounded down to the nearest quantity step.
    /// Short: The buyback also incurs a fee in coins. We therefore buy back slightly more,
    ///        rounded up, to ensure the borrowed quantity can be fully repaid.
    ///        Borrowing interest is not included.
    private static func exitQuantity(filled: String, direction: TradeDirection, step: Decimal) -> String {
        let filledQty = decimal(filled)
        let adjusted: Decimal
        switch direction {
        case .long:
            adjusted = ExchangeDecimal.roundDown(filledQty * (1 - spotFeeRate), toIncrement: step)
        case .short:
            adjusted = ExchangeDecimal.roundUp(filledQty / (1 - spotFeeRate), toIncrement: step)
        }
        return ExchangeDecimal.format(adjusted, increment: step)
    }

    private static func hasFired(_ status: String) -> Bool {
        ["triggered", "filled"].contains(status.lowercased())
    }

    private static func hasEnded(_ status: String) -> Bool {
        ["cancelled", "deactivated", "rejected"].contains(status.lowercased())
    }

    private static func decimal(_ raw: String) -> Decimal {
        Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func describe(_ error: Error) -> String {
        if let api = error as? BybitAPIError { return api.userMessage }
        return error.localizedDescription
    }

    private var parsedEntryPrice: Decimal? {
        TradeCalculator.decimal(from: entryPrice, locale: .current)
    }

    private var parsedStopLoss: Decimal? {
        TradeCalculator.decimal(from: stopLossPrice, locale: .current)
    }

    private var parsedTakeProfit: Decimal? {
        TradeCalculator.decimal(from: takeProfitPrice, locale: .current)
    }
}

enum ConnectionStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
}

/// When SL and TP are placed as conditional orders.
nonisolated enum ProtectionTiming: String, CaseIterable, Identifiable, Sendable {
    case immediately = "Immediately"
    case afterFill = "After fill"

    var id: String { rawValue }
}
