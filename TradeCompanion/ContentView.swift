import SwiftUI

struct ContentView: View {
    @Bindable var model: TradePlannerViewModel

    var body: some View {
        TradePlannerView(model: model)
    }
}

#Preview {
    ContentView(model: TradePlannerViewModel())
}
