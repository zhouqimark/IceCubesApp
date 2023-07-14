import SwiftUI

private struct ShowToast: ViewModifier {
  @Binding private var isShow: Bool
  private var toastView: ToastView
  
  init(isShow: Binding<Bool>, info: String = "", _duration: Double = 1.0) {
    _isShow = isShow
    toastView = ToastView(isShow: isShow, info: LocalizedStringKey(info), duration: _duration)
  }
  func body(content: Content) -> some View {
    ZStack(alignment: .bottom) {
      content
      if isShow {
        toastView
      }
    }
  }
  
  private struct ToastView: View {
    @Binding var isShow: Bool
    let info: LocalizedStringKey
    @State private var isShowAnimation: Bool = true
    @State private var duration : Double
    
    init(isShow: Binding<Bool>, info: LocalizedStringKey, duration: Double = 1.0) {
      self._isShow = isShow
      self.info = info
      self.duration = duration
    }
    
    var body: some View {
      ZStack {
        Text(info)
          .font(.system(size: 12.0))
          .foregroundColor(.white)
          .frame(alignment: Alignment.center)
          .padding(10)
          .zIndex(1.0)
          .background(
            RoundedRectangle(cornerRadius: 12)
              .foregroundColor(.black)
              .opacity(0.6)
          )
      }
      .onAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
          isShowAnimation = false
        }
      }
      .frame(alignment: .bottom)
      .opacity(isShowAnimation ? 1 : 0)
      .edgesIgnoringSafeArea(.all)
      .onChange(of: isShowAnimation) { e in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          self.isShow = false
        }
      }
    }
  }
}

public extension View {
  func toast(isShow: Binding<Bool>, info: String = "", _duration: Double = 1.0) -> some View {
    modifier(ShowToast(isShow: isShow, info: info, _duration: _duration))
  }
}
