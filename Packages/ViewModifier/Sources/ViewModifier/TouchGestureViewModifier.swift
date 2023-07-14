import SwiftUI

@available(iOS 13.0, *)
private struct TouchGestureViewModifier: ViewModifier {
  @GestureState private var triggerOnce: Bool = false
  private var onTouch: (CGPoint) -> Void
  public func body(content: Content) -> some View {
    content
      .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .updating($triggerOnce) { value, state, _ in
          if !state {
            state = true
            onTouch(value.location)
          }
        }
      )
  }
  public init(_ onTouch: @escaping (CGPoint) -> Void) {
    self.onTouch = onTouch
  }
}

@available(iOS 13.0, *)
public extension View {
  func onTouchGesture(onTouch: @escaping (CGPoint) -> Void) -> some View {
    modifier(TouchGestureViewModifier(onTouch))
  }
}
