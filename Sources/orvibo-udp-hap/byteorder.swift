//
//  byteorder.swift
//
//  Created by Rene Hexel on 4/6/17.
//  Copyright © 2017 Rene Hexel. All rights reserved.
//
import Foundation

fileprivate let bigEndian = 1.bigEndian == 1    // true if host is big endian

/// Convert port number from host to network byte order
///
/// - Parameter port: number in host byte order
/// - Returns: port number in network byte order
func htons(_ port: in_port_t) -> in_port_t {
    return bigEndian ? port : port.bigEndian
}

/// Convert port number from network to host byte order
///
/// - Parameter port: number in network byte order
/// - Returns: port number in host byte order
func ntohs(_ port: in_port_t) -> in_port_t {
    return bigEndian ? port : port.byteSwapped
}

/// Convert IPv4 address from host to network byte order
///
/// - Parameter addr: IPv4 address in host byte order
/// - Returns: IP address in network byte order
func htonl(_ addr: in_addr_t) -> in_addr_t {
    return bigEndian ? addr : addr.bigEndian
}

/// Convert IPv4 address from network to host byte order
///
/// - Parameter addr: IPv4 address in network byte order
/// - Returns: IP address in host byte order
func ntohl(_ addr: in_addr_t) -> in_addr_t {
    return bigEndian ? addr : addr.byteSwapped
}

/// Convert Int64 from network to host byte order
///
/// - Parameter value: Value in network byte order
/// - Returns: Value in host byte order
func ntohll(_ value: Int64) -> Int64 {
    return bigEndian ? value : value.byteSwapped
}

/// Convert UInt64 from network to host byte order
///
/// - Parameter value: Value in network byte order
/// - Returns: Value in host byte order
func ntohll(_ value: UInt64) -> UInt64 {
    return bigEndian ? value : value.byteSwapped
}

public func htonll(_ value: UInt64) -> UInt64 { return bigEndian ? value : value.bigEndian }

public func htohs(_ port: in_port_t) -> in_port_t { return bigEndian ? port : port.byteSwapped }
public func htohl(_ addr: in_addr_t) -> in_addr_t { return bigEndian ? addr : addr.byteSwapped }

public protocol NetworkByteOrderConvertible {
    var networkByteOrder: Self { get mutating set }
    init(fromNetwork: Self)
}

