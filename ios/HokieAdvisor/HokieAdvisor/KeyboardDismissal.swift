import SwiftUI
import UIKit
import Combine

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct KeyboardVisibilityModifier: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                onChange(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                onChange(false)
            }
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
    func onKeyboardVisibilityChange(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(KeyboardVisibilityModifier(onChange: onChange))
    }

    func swipeDownToDismissKeyboard() -> some View {
        modifier(SwipeDownKeyboardDismissModifier())
    }
}
