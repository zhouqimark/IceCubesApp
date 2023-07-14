import Foundation
public class MaskingVisible: ObservableObject {
  @Published public private(set) var visible: Bool = false
  
  public init() {}
  public func toggle() -> Void {
    visible = !visible
  }
}
