import SwiftUI
import Env

private struct EnableMaskingViewModifier: ViewModifier {
  @ObservedObject private var maskingVisible: MaskingVisible
  init(maskingVisible: MaskingVisible) {
    self.maskingVisible = maskingVisible
  }
  
  func body(content: Content) -> some View {
    content
      .overlay {
        if maskingVisible.visible {
          Color.black
            .opacity(0.1)
            .edgesIgnoringSafeArea(.all)
            .onTouchGesture { _ in
              DispatchQueue.main.async {
                maskingVisible.toggle()
              }
            }
        }
      }
  }
}

public extension View {
  func enableMasking(isPresented: MaskingVisible) -> some View {
    modifier(EnableMaskingViewModifier(maskingVisible: isPresented))
  }
}
