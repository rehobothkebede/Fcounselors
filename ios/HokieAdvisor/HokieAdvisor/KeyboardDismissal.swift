import SwiftUI
import UIKit

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct SwipeDownKeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        let verticalDrag = value.translation.height
                        let horizontalDrift = abs(value.translation.width)
                        if verticalDrag > 36 && horizontalDrift < 120 {
                            UIApplication.shared.dismissKeyboard()
                        }
                    }
            )
    }
}

extension View {
    func swipeDownToDismissKeyboard() -> some View {
        modifier(SwipeDownKeyboardDismissModifier())
    }
}

struct KeyboardDismissHandle: View {
    var body: some View {
        Capsule()
            .fill(Color(.tertiaryLabel).opacity(0.45))
            .frame(width: 42, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onEnded { value in
                        if value.translation.height > 10 {
                            UIApplication.shared.dismissKeyboard()
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}
