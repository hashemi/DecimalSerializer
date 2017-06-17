//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

//===----------------------------------------------------------------------===//
// JSON Decoder
//===----------------------------------------------------------------------===//

/// `JSONDecoder` facilitates the decoding of JSON into semantic `Decodable` types.
open class DecimalJSONDecoder {
    // MARK: Options

    /// The strategy to use for decoding `Date` values.
    public enum DateDecodingStrategy {
        /// Defer to `Date` for decoding. This is the default strategy.
        case deferredToDate

        /// Decode the `Date` as a UNIX timestamp from a JSON number.
        case secondsSince1970

        /// Decode the `Date` as UNIX millisecond timestamp from a JSON number.
        case millisecondsSince1970

        /// Decode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601

        /// Decode the `Date` as a string parsed by the given formatter.
        case formatted(DateFormatter)

        /// Decode the `Date` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Date)
    }

    /// The strategy to use for decoding `Data` values.
    public enum DataDecodingStrategy {
        /// Decode the `Data` from a Base64-encoded string. This is the default strategy.
        case base64Decode

        /// Decode the `Data` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Data)
    }

    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatDecodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`

        /// Decode the values from the given representation strings.
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate

    /// The strategy to use in decoding binary data. Defaults to `.base64Decode`.
    open var dataDecodingStrategy: DataDecodingStrategy = .base64Decode

    /// The strategy to use in decoding non-conforming numbers. Defaults to `.throw`.
    open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw

    /// Contextual user-provided information for use during decoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]

    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dateDecodingStrategy: DateDecodingStrategy
        let dataDecodingStrategy: DataDecodingStrategy
        let nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        let userInfo: [CodingUserInfoKey : Any]
    }

    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        return _Options(dateDecodingStrategy: dateDecodingStrategy,
                        dataDecodingStrategy: dataDecodingStrategy,
                        nonConformingFloatDecodingStrategy: nonConformingFloatDecodingStrategy,
                        userInfo: userInfo)
    }

    // MARK: - Constructing a JSON Decoder

    /// Initializes `self` with default strategies.
    public init() {}

    // MARK: - Decoding Values

    /// Decodes a top-level value of the given type from the given JSON representation.
    ///
    /// - parameter type: The type of the value to decode.
    /// - parameter data: The data to decode from.
    /// - returns: A value of the requested type.
    /// - throws: `DecodingError.dataCorrupted` if values requested from the payload are corrupted, or if the given data is not valid JSON.
    /// - throws: An error if any value throws an error during decoding.
    open func decode<T : Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let topLevel = try DecimalJSONSerialization.jsonObject(with: data)
        let decoder = _DecimalJSONDecoder(referencing: topLevel, options: self.options)
        return try T(from: decoder)
    }
}

// MARK: - _JSONDecoder

fileprivate class _DecimalJSONDecoder : Decoder {
    // MARK: Properties

    /// The decoder's storage.
    var storage: _DecimalJSONDecodingStorage

    /// Options set on the top-level decoder.
    let options: DecimalJSONDecoder._Options

    /// The path to the current point in encoding.
    var codingPath: [CodingKey?]

    /// Contextual user-provided information for use during encoding.
    var userInfo: [CodingUserInfoKey : Any] {
        return self.options.userInfo
    }

    // MARK: - Initialization

    /// Initializes `self` with the given top-level container and options.
    init(referencing container: Any, at codingPath: [CodingKey?] = [], options: DecimalJSONDecoder._Options) {
        self.storage = _DecimalJSONDecodingStorage()
        self.storage.push(container: container)
        self.codingPath = codingPath
        self.options = options
    }

    // MARK: - Coding Path Operations

    /// Performs the given closure with the given key pushed onto the end of the current coding path.
    ///
    /// - parameter key: The key to push. May be nil for unkeyed containers.
    /// - parameter work: The work to perform with the key in the path.
    func with<T>(pushedKey key: CodingKey?, _ work: () throws -> T) rethrows -> T {
        self.codingPath.append(key)
        let ret: T = try work()
        self.codingPath.removeLast()
        return ret
    }

    // MARK: - Decoder Methods

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard !(self.storage.topContainer is NSNull) else {
            throw DecodingError.valueNotFound(KeyedDecodingContainer<Key>.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Cannot get keyed decoding container -- found null value instead."))
        }

        guard let topContainer = self.storage.topContainer as? [String : Any] else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: [String : Any].self, reality: self.storage.topContainer)
        }

        let container = _JSONKeyedDecodingContainer<Key>(referencing: self, wrapping: topContainer)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !(self.storage.topContainer is NSNull) else {
            throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Cannot get unkeyed decoding container -- found null value instead."))
        }

        guard let topContainer = self.storage.topContainer as? [Any] else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: [Any].self, reality: self.storage.topContainer)
        }

        return _DecimalJSONUnkeyedDecodingContainer(referencing: self, wrapping: topContainer)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return self
    }
}

// MARK: - Decoding Storage

fileprivate struct _DecimalJSONDecodingStorage {
    // MARK: Properties

    /// The container stack.
    /// Elements may be any one of the JSON types (NSNull, NSNumber, String, Array, [String : Any]).
    private(set) var containers: [Any] = []

    // MARK: - Initialization

    /// Initializes `self` with no containers.
    init() {}

    // MARK: - Modifying the Stack

    var count: Int {
        return self.containers.count
    }

    var topContainer: Any {
        precondition(self.containers.count > 0, "Empty container stack.")
        return self.containers.last!
    }

    mutating func push(container: Any) {
        self.containers.append(container)
    }

    mutating func popContainer() {
        precondition(self.containers.count > 0, "Empty container stack.")
        self.containers.removeLast()
    }
}

// MARK: Decoding Containers

fileprivate struct _JSONKeyedDecodingContainer<K : CodingKey> : KeyedDecodingContainerProtocol {
    typealias Key = K

    // MARK: Properties

    /// A reference to the decoder we're reading from.
    let decoder: _DecimalJSONDecoder

    /// A reference to the container we're reading from.
    let container: [String : Any]

    /// The path of coding keys taken to get to this point in decoding.
    var codingPath: [CodingKey?]

    // MARK: - Initialization

    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: _DecimalJSONDecoder, wrapping container: [String : Any]) {
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
    }

    // MARK: - KeyedDecodingContainerProtocol Methods

    var allKeys: [Key] {
        return self.container.keys.flatMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        return self.container[key.stringValue] != nil
    }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        return try self.decoder.with(pushedKey: key) {
            return try self.decoder.unbox(self.container[key.stringValue], as: Bool.self)
        }
    }
    
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
        return try self.decoder.with(pushedKey: key) {
            return try self.decoder.unbox(self.container[key.stringValue], as: String.self)
        }
    }

    func decodeIfPresent(_ type: Data.Type, forKey key: Key) throws -> Data? {
        return try self.decoder.with(pushedKey: key) {
            return try self.decoder.unbox(self.container[key.stringValue], as: Data.self)
        }
    }

    func decodeIfPresent<T : Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        return try self.decoder.with(pushedKey: key) {
            return try self.decoder.unbox(self.container[key.stringValue], as: T.self)
        }
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        return try self.decoder.with(pushedKey: key) {
            guard let value = self.container[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: self.codingPath,
                                                                      debugDescription: "Cannot get \(KeyedDecodingContainer<NestedKey>.self) -- no value found for key \"\(key.stringValue)\""))
            }

            guard let dictionary = value as? [String : Any] else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: [String : Any].self, reality: value)
            }

            let container = _JSONKeyedDecodingContainer<NestedKey>(referencing: self.decoder, wrapping: dictionary)
            return KeyedDecodingContainer(container)
        }
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return try self.decoder.with(pushedKey: key) {
            guard let value = self.container[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: self.codingPath,
                                                                      debugDescription: "Cannot get UnkeyedDecodingContainer -- no value found for key \"\(key.stringValue)\""))
            }

            guard let array = value as? [Any] else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: [Any].self, reality: value)
            }

            return _DecimalJSONUnkeyedDecodingContainer(referencing: self.decoder, wrapping: array)
        }
    }

    func _superDecoder(forKey key: CodingKey) throws -> Decoder {
        return try self.decoder.with(pushedKey: key) {
            guard let value = self.container[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: self.codingPath,
                                                                      debugDescription: "Cannot get superDecoder() -- no value found for key \"\(key.stringValue)\""))
            }

            return _DecimalJSONDecoder(referencing: value, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }

    func superDecoder() throws -> Decoder {
        return try _superDecoder(forKey: _DecimalJSONSuperKey.super)
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        return try _superDecoder(forKey: key)
    }
}

fileprivate struct _DecimalJSONUnkeyedDecodingContainer : UnkeyedDecodingContainer {
    // MARK: Properties

    /// A reference to the decoder we're reading from.
    let decoder: _DecimalJSONDecoder

    /// A reference to the container we're reading from.
    let container: [Any]

    /// The path of coding keys taken to get to this point in decoding.
    var codingPath: [CodingKey?]

    /// The index of the element we're about to decode.
    var currentIndex: Int

    // MARK: - Initialization

    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: _DecimalJSONDecoder, wrapping container: [Any]) {
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
        self.currentIndex = 0
    }

    // MARK: - UnkeyedDecodingContainer Methods

    var count: Int? {
        return self.container.count
    }

    var isAtEnd: Bool {
        return self.currentIndex >= self.count!
    }

    mutating func decodeIfPresent(_ type: Bool.Type) throws -> Bool? {
        guard !self.isAtEnd else { return nil }

        return try self.decoder.with(pushedKey: nil) {
            let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Bool.self)
            self.currentIndex += 1
            return decoded
        }
    }
    
    mutating func decodeIfPresent(_ type: String.Type) throws -> String? {
        guard !self.isAtEnd else { return nil }

        return try self.decoder.with(pushedKey: nil) {
            let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: String.self)
            self.currentIndex += 1
            return decoded
        }
    }

    mutating func decodeIfPresent(_ type: Data.Type) throws -> Data? {
        guard !self.isAtEnd else { return nil }

        return try self.decoder.with(pushedKey: nil) {
            let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Data.self)
            self.currentIndex += 1
            return decoded
        }
    }

    mutating func decodeIfPresent<T : Decodable>(_ type: T.Type) throws -> T? {
        guard !self.isAtEnd else { return nil }

        return try self.decoder.with(pushedKey: nil) {
            let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: T.self)
            self.currentIndex += 1
            return decoded
        }
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        return try self.decoder.with(pushedKey: nil) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end."))
            }

            let value = self.container[self.currentIndex]
            guard !(value is NSNull) else {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get keyed decoding container -- found null value instead."))
            }

            guard let dictionary = value as? [String : Any] else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: [String : Any].self, reality: value)
            }

            self.currentIndex += 1
            let container = _JSONKeyedDecodingContainer<NestedKey>(referencing: self.decoder, wrapping: dictionary)
            return KeyedDecodingContainer(container)
        }
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try self.decoder.with(pushedKey: nil) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end."))
            }

            let value = self.container[self.currentIndex]
            guard !(value is NSNull) else {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get keyed decoding container -- found null value instead."))
            }

            guard let array = value as? [Any] else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: [Any].self, reality: value)
            }

            self.currentIndex += 1
            return _DecimalJSONUnkeyedDecodingContainer(referencing: self.decoder, wrapping: array)
        }
    }

    mutating func superDecoder() throws -> Decoder {
        return try self.decoder.with(pushedKey: nil) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(Decoder.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get superDecoder() -- unkeyed container is at end."))
            }

            let value = self.container[self.currentIndex]
            guard !(value is NSNull) else {
                throw DecodingError.valueNotFound(Decoder.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get superDecoder() -- found null value instead."))
            }

            self.currentIndex += 1
            return _DecimalJSONDecoder(referencing: value, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }
}

extension _DecimalJSONDecoder : SingleValueDecodingContainer {
    // MARK: SingleValueDecodingContainer Methods

    func decodeNil() -> Bool {
        return self.storage.topContainer is NSNull
    }

    // These all unwrap the result, since we couldn't have gotten a single value container if the topContainer was null.
    func decode(_ type: Bool.Type) throws -> Bool {
        guard let value = try self.unbox(self.storage.topContainer, as: Bool.self) else {
            throw DecodingError.valueNotFound(Bool.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Expected Bool but found null value instead."))
        }

        return value
    }

    func decode(_ type: String.Type) throws -> String {
        guard let value = try self.unbox(self.storage.topContainer, as: String.self) else {
            throw DecodingError.valueNotFound(String.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Expected String but found null value instead."))
        }

        return value
    }

    func decode<T : Decodable>(_ type: T.Type) throws -> T {
        guard let value = try self.unbox(self.storage.topContainer, as: T.self) else {
            throw DecodingError.valueNotFound(T.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Expected \(T.self) but found null value instead."))
        }

        return value
    }
}

// MARK: - Concrete Value Representations

extension _DecimalJSONDecoder {
    /// Returns the given value unboxed from a container.
    fileprivate func unbox(_ value: Any?, as type: Bool.Type) throws -> Bool? {
        guard let value = value else { return nil }
        guard !(value is NSNull) else { return nil }

        
        if let bool = value as? Bool {
            return bool
        }

        throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: value)
    }
    
    func unbox(_ value: Any?, as type: Decimal.Type) throws -> Decimal? {
        guard let value = value else { return nil }
        guard !(value is NSNull) else { return nil }
        
        guard let decimal = value as? Decimal else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: value)
        }
        
        return decimal
    }
    
    func unbox(_ value: Any?, as type: String.Type) throws -> String? {
        guard let value = value else { return nil }
        guard !(value is NSNull) else { return nil }

        guard let string = value as? String else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        return string
    }

    func unbox(_ value: Any?, as type: Date.Type) throws -> Date? {
        guard let value = value else { return nil }
        guard !(value is NSNull) else { return nil }

        switch self.options.dateDecodingStrategy {
        case .deferredToDate:
            self.storage.push(container: value)
            let date = try Date(from: self)
            self.storage.popContainer()
            return date

        case .secondsSince1970:
            let double = try self.unbox(value, as: Double.self)!
            return Date(timeIntervalSince1970: double)

        case .millisecondsSince1970:
            let double = try self.unbox(value, as: Double.self)!
            return Date(timeIntervalSince1970: double / 1000.0)

        case .iso8601:
            if #available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                let string = try self.unbox(value, as: String.self)!
                guard let date = _iso8601Formatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
                }

                return date
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }

        case .formatted(let formatter):
            let string = try self.unbox(value, as: String.self)!
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Date string does not match format expected by formatter."))
            }

            return date

        case .custom(let closure):
            self.storage.push(container: value)
            let date = try closure(self)
            self.storage.popContainer()
            return date
        }
    }

    func unbox(_ value: Any?, as type: Data.Type) throws -> Data? {
        guard let value = value else { return nil }
        guard !(value is NSNull) else { return nil }

        switch self.options.dataDecodingStrategy {
        case .base64Decode:
            guard let string = value as? String else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: value)
            }

            guard let data = Data(base64Encoded: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Data is not valid Base64."))
            }

            return data

        case .custom(let closure):
            self.storage.push(container: value)
            let data = try closure(self)
            self.storage.popContainer()
            return data
        }
    }

    func unbox<T : Decodable>(_ value: Any?, as type: T.Type) throws -> T? {
        guard let value = value else { return nil }
        guard !(value is NSNull) else { return nil }

        let decoded: T
        if T.self == Date.self {
            decoded = (try self.unbox(value, as: Date.self) as! T)
        } else if T.self == Data.self {
            decoded = (try self.unbox(value, as: Data.self) as! T)
        } else if T.self == Decimal.self {
            decoded = (try self.unbox(value, as: Decimal.self) as! T)
        } else if T.self == URL.self {
            guard let urlString = try self.unbox(value, as: String.self) else {
                return nil
            }

            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Invalid URL string."))
            }

            decoded = (url as! T)
        } else {
            self.storage.push(container: value)
            decoded = try T(from: self)
            self.storage.popContainer()
        }

        return decoded
    }
}

//===----------------------------------------------------------------------===//
// Shared Super Key
//===----------------------------------------------------------------------===//

fileprivate enum _DecimalJSONSuperKey : String, CodingKey {
    case `super`
}

//===----------------------------------------------------------------------===//
// Shared ISO8601 Date Formatter
//===----------------------------------------------------------------------===//

// NOTE: This value is implicitly lazy and _must_ be lazy. We're compiled against the latest SDK (w/ ISO8601DateFormatter), but linked against whichever Foundation the user has. ISO8601DateFormatter might not exist, so we better not hit this code path on an older OS.
@available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
fileprivate var _iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    return formatter
}()

// This was copied and modified from Codable.swift

//===----------------------------------------------------------------------===//
// Error Utilities
//===----------------------------------------------------------------------===//
internal extension DecodingError {
    /// Returns a `.typeMismatch` error describing the expected type.
    ///
    /// - parameter path: The path of `CodingKey`s taken to decode a value of this type.
    /// - parameter expectation: The type expected to be encountered.
    /// - parameter reality: The value that was encountered instead of the expected type.
    /// - returns: A `DecodingError` with the appropriate path and debug description.
    fileprivate static func _typeMismatch(at path: [CodingKey?], expectation: Any.Type, reality: Any) -> DecodingError {
        let description = "Expected to decode \(expectation) but found \(_typeDescription(of: reality)) instead."
        return .typeMismatch(expectation, Context(codingPath: path, debugDescription: description))
    }
    
    /// Returns a description of the type of `value` appropriate for an error message.
    ///
    /// - parameter value: The value whose type to describe.
    /// - returns: A string describing `value`.
    /// - precondition: `value` is one of the types below.
    fileprivate static func _typeDescription(of value: Any) -> String {
        if value is NSNull {
            return "a null value"
        } else if value is Decimal {
            return "a decimal"
        } else if value is String {
            return "a string/data"
        } else if value is [Any] {
            return "an array"
        } else if value is [String : Any] {
            return "a dictionary"
        } else {
            // This should never happen -- we somehow have a non-JSON type here.
            preconditionFailure("Invalid storage type \(type(of: value)).")
        }
    }
}
