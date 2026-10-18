import Foundation

nonisolated struct BybitAPIClient: Sendable {
    var environment: BybitEnvironment
    var session: URLSession
    var now: @Sendable () -> Date

    init(
        environment: BybitEnvironment = .demo,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.environment = environment
        self.session = session
        self.now = now
    }

    func instrument(symbol: String, credentials: BybitCredentials?) async throws -> InstrumentConstraints {
        let query = "category=spot&symbol=\(symbol.uppercased())"
        let data = try await send(
            method: "GET",
            path: "/v5/market/instruments-info",
            query: query,
            jsonBody: nil,
            credentials: nil
        )
        let decoded: BybitEnvelope<BybitListResult<BybitInstrumentRow>> = try Self.decodeEnvelope(data)
        try decoded.requireSuccess()
        guard let row = decoded.result?.list.first else {
            throw BybitAPIError.instrumentNotFound(symbol.uppercased())
        }
        return try row.makeConstraints()
    }

    func checkConnection(credentials: BybitCredentials) async throws {
        let data = try await send(method: "GET", path: "/v5/account/info",
                                  query: "", jsonBody: nil, credentials: credentials)
        let decoded: BybitEnvelope<BybitEmptyResult> = try Self.decodeEnvelope(data)
        try decoded.requireSuccess()
    }

    private struct BybitEmptyResult: Decodable {}

    /// Step 1: Place the entry without TP/SL. These are placed separately using `placeConditional`.
    /// Long = Buy. Short = Sell with `isLeverage: 1` (spot margin; Bybit borrows the coins).
    func placeOrder(
        credentials: BybitCredentials,
        symbol: String,
        direction: TradeDirection,
        orderType: OrderEntryType,
        quantity: String,
        price: String?,
        orderLinkId: String
    ) async throws -> BybitPlacedOrder {
        var body: [String: Any] = [
            "category": "spot",
            "symbol": symbol.uppercased(),
            "side": direction.bybitSide,
            "orderType": orderType.bybitOrderType,
            "qty": quantity,
            "timeInForce": orderType == .market ? "IOC" : "GTC",
            "orderLinkId": orderLinkId,
        ]
        if orderType == .limit, let price {
            body["price"] = price
        }
        if orderType == .market {
            // Without this, the quantity of a market buy is specified in USDC instead of coins.
            body["marketUnit"] = "baseCoin"
        }
        if direction == .short {
            body["isLeverage"] = 1
        }
        return try await createOrder(credentials: credentials, body: body)
    }

    /// Steps 2 and 3: Place SL or TP as a conditional order (StopOrder with triggerPrice).
    /// The exit side is opposite to the entry side: long = Sell, short = Buy (with isLeverage: 1).
    /// triggerDirection: 1 = triggers when the price rises, 2 = triggers when the price falls.
    func placeConditional(
        credentials: BybitCredentials,
        symbol: String,
        direction: TradeDirection,
        kind: ConditionalKind,
        quantity: String,
        triggerPrice: String,
        orderLinkId: String
    ) async throws -> BybitPlacedOrder {
        let isLong = (direction == .long)

        // Long: SL triggers when the price falls (2), TP when it rises (1). The opposite applies to shorts.
        let triggerDirection: Int
        switch (kind, isLong) {
        case (.stopLoss, true), (.takeProfit, false): triggerDirection = 2
        case (.takeProfit, true), (.stopLoss, false): triggerDirection = 1
        }

        var body: [String: Any] = [
            "category": "spot",
            "symbol": symbol.uppercased(),
            "side": isLong ? "Sell" : "Buy",
            "orderType": "Market",
            "qty": quantity,
            "orderFilter": "StopOrder",
            "triggerPrice": triggerPrice,
            "triggerDirection": triggerDirection,
            "orderLinkId": orderLinkId,
        ]
        if !isLong {
            body["isLeverage"] = 1
        }
        return try await createOrder(credentials: credentials, body: body)
    }

    /// Cancels a regular order or a conditional order (`isConditional: true`).
    func cancelOrder(
        credentials: BybitCredentials,
        symbol: String,
        orderId: String,
        isConditional: Bool
    ) async throws {
        var body: [String: Any] = [
            "category": "spot",
            "symbol": symbol.uppercased(),
            "orderId": orderId,
        ]
        if isConditional {
            body["orderFilter"] = "StopOrder"
        }
        let json = try compactJSON(body)
        let data = try await send(
            method: "POST",
            path: "/v5/order/cancel",
            query: "",
            jsonBody: json,
            credentials: credentials
        )
        let decoded: BybitEnvelope<BybitEmptyResult> = try Self.decodeEnvelope(data)
        try decoded.requireSuccess()
    }

    /// Order status. For conditional orders, use `isConditional: true`.
    /// If the order is no longer available in real-time, check the order history.
    func order(
        credentials: BybitCredentials,
        symbol: String,
        orderId: String?,
        orderLinkId: String?,
        isConditional: Bool = false
    ) async throws -> BybitOrderRecord {
        var items: [String] = ["category=spot", "symbol=\(symbol.uppercased())"]
        if isConditional { items.append("orderFilter=StopOrder") }
        if let orderId, !orderId.isEmpty {
            items.append("orderId=\(orderId)")
        } else if let orderLinkId, !orderLinkId.isEmpty {
            items.append("orderLinkId=\(orderLinkId)")
        }
        let queryString = items.joined(separator: "&")

        for path in ["/v5/order/realtime", "/v5/order/history"] {
            let data = try await send(
                method: "GET",
                path: path,
                query: queryString,
                jsonBody: nil,
                credentials: credentials
            )
            let decoded: BybitEnvelope<BybitListResult<BybitOrderRow>> = try Self.decodeEnvelope(data)
            try decoded.requireSuccess()
            if let row = decoded.result?.list.first {
                return row.makeRecord()
            }
        }
        throw BybitAPIError.ambiguousOrderStatus(
            "Bybit accepted the request, but the order is not visible yet. Query the exchange before assuming a fill."
        )
    }

    private func createOrder(credentials: BybitCredentials, body: [String: Any]) async throws -> BybitPlacedOrder {
        let json = try compactJSON(body)
        let data = try await send(
            method: "POST",
            path: "/v5/order/create",
            query: "",
            jsonBody: json,
            credentials: credentials
        )
        let decoded: BybitEnvelope<BybitPlaceOrderResult> = try Self.decodeEnvelope(data)
        try decoded.requireSuccess()
        guard let result = decoded.result, !result.orderId.isEmpty else {
            throw BybitAPIError.emptyResult
        }
        return BybitPlacedOrder(orderId: result.orderId, orderLinkId: result.orderLinkId ?? "")
    }

    static func decodeEnvelope<T: Decodable>(_ data: Data) throws -> BybitEnvelope<T> {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(BybitEnvelope<T>.self, from: data)
        } catch let error as DecodingError {
            throw BybitAPIError.decoding(describe(error))
        } catch {
            throw BybitAPIError.decoding(error.localizedDescription)
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing field '\(key.stringValue)' at '\(path(context))'."
        case .typeMismatch(_, let context):
            return "Unexpected type at '\(path(context))': \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "Empty value at '\(path(context))'."
        case .dataCorrupted(let context):
            return "Corrupted data at '\(path(context))': \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func send(
        method: String,
        path: String,
        query: String,
        jsonBody: String?,
        credentials: BybitCredentials?
    ) async throws -> Data {
        guard let endpoint = URL(string: path, relativeTo: environment.restBaseURL)?.absoluteURL else {
            throw BybitAPIError.invalidURL
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.percentEncodedQuery = query
        }
        guard let url = components?.url else {
            throw BybitAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let jsonBody {
            request.httpBody = Data(jsonBody.utf8)
        }

        if let credentials {
            guard credentials.isComplete else {
                throw BybitAPIError.missingCredentials
            }
            let timestamp = String(Int((now().timeIntervalSince1970 * 1000).rounded(.down)))
            let payload = method == "GET" ? query : (jsonBody ?? "")
            let signPayload = BybitSigning.payloadString(
                timestamp: timestamp,
                apiKey: credentials.apiKey,
                recvWindow: BybitSigning.recvWindowMilliseconds,
                body: payload
            )
            let signature = BybitSigning.hmacSignature(secret: credentials.apiSecret, payload: signPayload)
            request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
            request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
            request.setValue(BybitSigning.recvWindowMilliseconds, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
            request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("Bybit URL:", url.absoluteString)
                print("HTTP status:", http.statusCode)
                print("Response body:", String(data: data, encoding: .utf8) ?? "<not UTF-8>")
            }
        } catch {
            throw BybitAPIError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw BybitAPIError.httpStatus(http.statusCode, responseBody)
        }

        return data
    }

    private func compactJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw BybitAPIError.decoding("Could not encode the order body.")
        }
        return text
    }
}

nonisolated enum ConditionalKind: Sendable {
    case stopLoss
    case takeProfit
}

nonisolated struct BybitEnvelope<Result: Decodable>: Decodable {
    var retCode: Int
    var retMsg: String
    var result: Result?

    func requireSuccess() throws {
        if retCode != 0 {
            throw BybitAPIError.rejected(code: retCode, message: retMsg)
        }
    }
}

private struct BybitListResult<Item: Decodable>: Decodable {
    var list: [Item]
}

private struct BybitPlaceOrderResult: Decodable {
    var orderId: String
    var orderLinkId: String?
}

private struct BybitInstrumentRow: Decodable {
    var symbol: String
    var status: String?
    var baseCoin: String?
    var quoteCoin: String?
    var contractType: String?   // Only for derivatives.
    var settleCoin: String?     // Only for derivatives.
    var priceFilter: PriceFilter?
    var lotSizeFilter: LotSizeFilter?

    struct PriceFilter: Decodable {
        var tickSize: String?
    }

    struct LotSizeFilter: Decodable {
        var basePrecision: String?
        var qtyStep: String?
        var minOrderQty: String?
        var maxOrderQty: String?
        var maxLimitOrderQty: String?
        var maxMarketOrderQty: String?
        var maxMktOrderQty: String?
        var minOrderAmt: String?
        var minNotionalValue: String?
    }

    private var resolvedQuote: String {
        if let quoteCoin, !quoteCoin.isEmpty { return quoteCoin }
        for suffix in ["USDT", "USDC", "EUR", "PLN"] where symbol.hasSuffix(suffix) {
            return suffix
        }
        return ""
    }

    private var resolvedBase: String {
        if let baseCoin, !baseCoin.isEmpty { return baseCoin }
        let quote = resolvedQuote
        return quote.isEmpty ? symbol : String(symbol.dropLast(quote.count))
    }

    func makeConstraints() throws -> InstrumentConstraints {
        guard let tick = decimal(priceFilter?.tickSize) else {
            throw BybitAPIError.decoding("priceFilter.tickSize is missing for \(symbol).")
        }
        guard let step = decimal(lotSizeFilter?.basePrecision) ?? decimal(lotSizeFilter?.qtyStep) else {
            throw BybitAPIError.decoding("lotSizeFilter.basePrecision is missing for \(symbol).")
        }
        let minQty = decimal(lotSizeFilter?.minOrderQty) ?? 0
        let maxQty = decimal(lotSizeFilter?.maxOrderQty)
            ?? decimal(lotSizeFilter?.maxLimitOrderQty)
            ?? Decimal(1_000_000_000_000)
        let maxMarket = decimal(lotSizeFilter?.maxMarketOrderQty)
            ?? decimal(lotSizeFilter?.maxMktOrderQty)
            ?? maxQty
        let minNotional = decimal(lotSizeFilter?.minOrderAmt)
            ?? decimal(lotSizeFilter?.minNotionalValue)
            ?? 0

        return InstrumentConstraints(
            symbol: symbol,
            contractType: contractType ?? "Spot",
            status: status ?? "Trading",
            baseCoin: resolvedBase,
            quoteCoin: resolvedQuote,
            settleCoin: settleCoin ?? resolvedQuote,
            tickSize: tick,
            qtyStep: step,
            minOrderQty: minQty,
            maxOrderQty: maxQty,
            maxMarketOrderQty: maxMarket,
            minNotionalValue: minNotional
        )
    }
}

private struct BybitOrderRow: Decodable {
    var orderId: String
    var orderLinkId: String?
    var symbol: String
    var side: String
    var orderType: String
    var price: String?
    var qty: String
    var orderStatus: String
    var rejectReason: String?
    var avgPrice: String?
    var cumExecQty: String?
    var takeProfit: String?
    var stopLoss: String?
    var leavesQty: String?

    func makeRecord() -> BybitOrderRecord {
        BybitOrderRecord(
            orderId: orderId,
            orderLinkId: orderLinkId ?? "",
            symbol: symbol,
            side: side,
            orderType: orderType,
            price: price ?? "",
            qty: qty,
            orderStatus: orderStatus,
            rejectReason: rejectReason ?? "",
            avgPrice: avgPrice ?? "",
            cumExecQty: cumExecQty ?? "",
            takeProfit: takeProfit ?? "",
            stopLoss: stopLoss ?? "",
            leavesQty: leavesQty ?? ""
        )
    }
}

private func decimal(_ raw: String?) -> Decimal? {
    guard let raw, !raw.isEmpty else { return nil }
    return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
}
