import Foundation
import Testing
@testable import TradeCompanion

struct BybitAPIClientTests {
    @Test func hmacSignatureMatchesKnownVector() {
        let payload = BybitSigning.payloadString(
            timestamp: "1658385579423",
            apiKey: "XXXXXXXXXX",
            recvWindow: "5000",
            body: "{\"category\":\"option\"}"
        )
        #expect(payload == "1658385579423XXXXXXXXXX5000{\"category\":\"option\"}")
        let signature = BybitSigning.hmacSignature(secret: "testsecret", payload: payload)
        #expect(signature == "4304e2f8d0bb0c22c35fdc11179290f47bdce4c88908dfd457d52785275f17ef")
    }

    @Test func rejectedOrderEnvelopeBecomesAPIError() throws {
        let json = """
        {"retCode":10001,"retMsg":"Qty invalid","result":{},"retExtInfo":{},"time":1}
        """
        let data = Data(json.utf8)
        let decoded: BybitEnvelope<EmptyResult> = try BybitAPIClient.decodeEnvelope(data)
        #expect(throws: BybitAPIError.rejected(code: 10001, message: "Qty invalid")) {
            try decoded.requireSuccess()
        }
    }

    @Test func successfulPlaceOrderEnvelopeDecodesIdentifiers() throws {
        let json = """
        {"retCode":0,"retMsg":"OK","result":{"orderId":"abc","orderLinkId":"tc-1"},"retExtInfo":{},"time":1}
        """
        let decoded: BybitEnvelope<PlaceOrderStub> = try BybitAPIClient.decodeEnvelope(Data(json.utf8))
        try decoded.requireSuccess()
        #expect(decoded.result?.orderId == "abc")
        #expect(decoded.result?.orderLinkId == "tc-1")
    }

    @Test func demoEnvironmentUsesOfficialDemoHost() {
        #expect(BybitEnvironment.demo.restBaseURL.absoluteString == "https://api-demo.bybit.com")
    }

    @Test func linearPerpetualUSDTIsSupported() {
        let spec = InstrumentConstraints(
            symbol: "BTCUSDT",
            contractType: "LinearPerpetual",
            status: "Trading",
            baseCoin: "BTC",
            quoteCoin: "USDT",
            settleCoin: "USDT",
            tickSize: 0.1,
            qtyStep: 0.001,
            minOrderQty: 0.001,
            maxOrderQty: 100,
            maxMarketOrderQty: 50,
            minNotionalValue: 5
        )
        #expect(spec.supportsLinearPlannerFormulas)
    }
}

private struct EmptyResult: Decodable {}

private struct PlaceOrderStub: Decodable {
    var orderId: String
    var orderLinkId: String
}
