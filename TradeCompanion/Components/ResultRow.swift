import SwiftUI

struct ResultRow: View {
    let title: String
    let value: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}
