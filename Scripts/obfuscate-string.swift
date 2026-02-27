#!/usr/bin/env swift
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("Usage: obfuscate-string.swift <string>")
    exit(1)
}

let input = CommandLine.arguments[1]
let bytes = Array(input.utf8)
var key = [UInt8](repeating: 0, count: bytes.count)

for i in 0..<bytes.count {
    key[i] = UInt8.random(in: 1...255)
}

let data = zip(bytes, key).map { $0 ^ $1 }

print("data: [\(data.map { "0x\(String(format: "%02X", $0))" }.joined(separator: ", "))]")
print("key:  [\(key.map { "0x\(String(format: "%02X", $0))" }.joined(separator: ", "))]")
