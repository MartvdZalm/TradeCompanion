import Foundation

nonisolated enum BybitEnvironment: String, Sendable {
    case demo

    var displayName: String { "DEMO" }

    var restBaseURL: URL {
        switch self {
        case .demo:
            return URL(string: "https://api-demo.bybit.eu")!
        }
    }
}

nonisolated struct BybitCredentials: Sendable {
    var apiKey: String
    var apiSecret: String

    var isComplete: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

nonisolated enum BybitAPIError: Equatable, Error, Sendable {
    case missingCredentials
    case invalidURL
    case transport(String)
    case httpStatus(Int, String)
    case decoding(String)
    case rejected(code: Int, message: String)
    case emptyResult
    case instrumentNotFound(String)
    case ambiguousOrderStatus(String)

    var userMessage: String {
        switch self {
        case .missingCredentials:
            return "Bybit Demo API keys are not configured."
        case .invalidURL:
            return "The Bybit request URL is invalid."
        case .transport(let message):
            return "Network error: \(message)"
        case .httpStatus(let status, let body):
            return "Bybit returned HTTP \(status): \(body)"
        case .decoding(let message):
            return "Could not read the Bybit response. \(message)"
        case .rejected(let code, let message):
            return "Bybit rejected the request (\(code)): \(message)"
        case .emptyResult:
            return "Bybit returned no data."
        case .instrumentNotFound(let symbol):
            return "No spot instrument named \(symbol) was found on Bybit Demo."
        case .ambiguousOrderStatus(let detail):
            return detail
        }
    }
}

nonisolated struct BybitWalletSnapshot: Equatable, Sendable {
    var accountType: String
    var totalEquity: Decimal?
    var totalWalletBalance: Decimal?
    var totalAvailableBalance: Decimal?
    var coins: [BybitCoinBalance]
}

nonisolated struct BybitCoinBalance: Equatable, Sendable {
    var coin: String
    var walletBalance: Decimal?
    var equity: Decimal?
}

nonisolated struct BybitPlacedOrder: Equatable, Sendable {
    var orderId: String
    var orderLinkId: String
}

nonisolated struct BybitOrderRecord: Equatable, Sendable {
    var orderId: String
    var orderLinkId: String
    var symbol: String
    var side: String
    var orderType: String
    var price: String
    var qty: String
    var orderStatus: String
    var rejectReason: String
    var avgPrice: String
    var cumExecQty: String
    var takeProfit: String
    var stopLoss: String
    var leavesQty: String
}

nonisolated struct OrderPreview: Equatable, Sendable {
    var environment: String
    var symbol: String
    var direction: TradeDirection
    var orderType: OrderEntryType
    var entryDescription: String
    var quantity: String
    var orderValue: String
    var stopLoss: String
    var takeProfit: String
    var plannedLoss: String
    var riskReward: String
}
