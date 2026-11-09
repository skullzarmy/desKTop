import Foundation

public struct TestFailure: Error {
    public let message: String
    public let file: String
    public let line: Int

    public init(_ message: String, file: String = #fileID, line: Int = #line) {
        self.message = message
        self.file = file
        self.line = line
    }
}

public func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if a != b {
        throw TestFailure("Expected \(a) == \(b). \(message)", file: file, line: line)
    }
}

public func assertTrue(_ condition: Bool, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if !condition {
        throw TestFailure("Expected condition to be true. \(message)", file: file, line: line)
    }
}

public func assertFalse(_ condition: Bool, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if condition {
        throw TestFailure("Expected condition to be false. \(message)", file: file, line: line)
    }
}

public func assertNil(_ value: Any?, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if value != nil {
        throw TestFailure("Expected value to be nil, got \(String(describing: value)). \(message)", file: file, line: line)
    }
}

public func assertNotNil(_ value: Any?, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if value == nil {
        throw TestFailure("Expected value to not be nil. \(message)", file: file, line: line)
    }
}
