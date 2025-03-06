import SwiftUI

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.accentColor)
            
            Text(text)
                .font(.body)
        }
    }
} 