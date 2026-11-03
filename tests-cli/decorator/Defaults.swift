@_exported import SwiftUI

public enum HighlightMatch {
  case bold, italic, underline, background
}
public enum Defaults {
  public struct Key<Value> {
    public let value: Value
    public init(_ value: Value) { self.value = value }
  }
  public static subscript<Value>(key: Key<Value>) -> Value { key.value }
}
public extension Defaults.Key where Value == Int {
  static var previewDelay: Self { Self(200) }
  static var imageMaxHeight: Self { Self(40) }
}
public extension Defaults.Key where Value == HighlightMatch {
  static var highlightMatch: Self { Self(.bold) }
}
