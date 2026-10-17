import SwiftUI

struct InputField: View {
    let title: String
    @Binding var text: String
    var suffix: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
    }
}
