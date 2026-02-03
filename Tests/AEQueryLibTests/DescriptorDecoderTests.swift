import Testing
import Foundation
@testable import AEQueryLib

@Suite("DescriptorDecoder")
struct DescriptorDecoderTests {
    private let decoder = DescriptorDecoder()

    @Test func testDecodeString() {
        let desc = NSAppleEventDescriptor(string: "hello")
        let value = decoder.decode(desc)
        #expect(value == .string("hello"))
    }

    @Test func testDecodeInt32() {
        let desc = NSAppleEventDescriptor(int32: 42)
        let value = decoder.decode(desc)
        #expect(value == .integer(42))
    }

    @Test func testDecodeBoolTrue() {
        let desc = NSAppleEventDescriptor(boolean: true)
        let value = decoder.decode(desc)
        #expect(value == .bool(true))
    }

    @Test func testDecodeBoolFalse() {
        let desc = NSAppleEventDescriptor(boolean: false)
        let value = decoder.decode(desc)
        #expect(value == .bool(false))
    }

    @Test func testDecodeList() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "a"), at: 1)
        list.insert(NSAppleEventDescriptor(string: "b"), at: 2)
        list.insert(NSAppleEventDescriptor(string: "c"), at: 3)
        let value = decoder.decode(list)
        #expect(value == .list([.string("a"), .string("b"), .string("c")]))
    }

    @Test func testDecodeEmptyList() {
        let list = NSAppleEventDescriptor.list()
        let value = decoder.decode(list)
        #expect(value == .list([]))
    }

    @Test func testDecodeNestedList() {
        let inner = NSAppleEventDescriptor.list()
        inner.insert(NSAppleEventDescriptor(string: "nested"), at: 1)
        let outer = NSAppleEventDescriptor.list()
        outer.insert(inner, at: 1)
        let value = decoder.decode(outer)
        #expect(value == .list([.list([.string("nested")])]))
    }

    @Test func testDecodeRecord() {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(string: "test"), forKeyword: FourCharCode("pnam"))
        let value = decoder.decode(record)
        if case .record(let pairs) = value {
            #expect(pairs.count == 1)
            #expect(pairs[0].0 == "pnam")
            #expect(pairs[0].1 == .string("test"))
        } else {
            Issue.record("Expected .record")
        }
    }

    @Test func testDecodeNull() {
        let desc = NSAppleEventDescriptor.null()
        let value = decoder.decode(desc)
        #expect(value == .null)
    }
}
