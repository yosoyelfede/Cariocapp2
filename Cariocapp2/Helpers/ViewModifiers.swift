import SwiftUI

// MARK: - Loading Components
struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        Color.black
            .opacity(0.4)
            .ignoresSafeArea()
            .overlay {
                ProgressView(message)
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(8)
            }
    }
}

struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    let message: String
    
    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                LoadingOverlay(message: message)
            }
        }
    }
}

// MARK: - Error Handling
struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                }
            } message: {
                if let error = error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                        if let recovery = error.recoverySuggestion {
                            Text(recovery)
                                .font(.caption)
                        }
                    }
                }
            }
    }
}

// MARK: - Haptic Feedback
struct HapticButtonStyle: ButtonStyle {
    let feedbackType: UIImpactFeedbackGenerator.FeedbackStyle
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    HapticManager.playImpact(style: feedbackType)
                }
            }
    }
}

// MARK: - Accessibility
struct AccessibilityLabelModifier: ViewModifier {
    let label: String
    let hint: String?
    let traits: AccessibilityTraits
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits)
            .if(hint != nil) { view in
                view.accessibilityHint(hint!)
            }
    }
}

// MARK: - View Extensions
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    func loading(_ isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(LoadingModifier(isLoading: isLoading, message: message))
    }
    
    func errorAlert(error: Binding<AppError?>) -> some View {
        modifier(ErrorAlertModifier(error: error))
    }
    
    func withHaptics(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        buttonStyle(HapticButtonStyle(feedbackType: style))
    }
    
    func accessibilityLabel(_ label: String, hint: String? = nil, traits: AccessibilityTraits = []) -> some View {
        modifier(AccessibilityLabelModifier(label: label, hint: hint, traits: traits))
    }
} 