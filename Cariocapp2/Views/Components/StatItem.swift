import SwiftUI

struct StatItem: View {
    let title: String
    let value: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(value)
            }
            Text(title)
                .foregroundColor(.secondary)
        }
    }
} 