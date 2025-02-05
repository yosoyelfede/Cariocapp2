import SwiftUI

struct PlayerRow: View {
    let name: String
    let isGuest: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Text(name)
            if isGuest {
                Text("Guest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                    )
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
    }
} 