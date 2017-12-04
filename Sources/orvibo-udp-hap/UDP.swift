//
//  UDP.swift
//  orvibo
//
//  Created by Rene Hexel on 28/12/16.
//  Copyright © 2016, 2017 Rene Hexel. All rights reserved.
//
import Foundation
import Dispatch
#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

/// C-level file descriptor or socket
public typealias CFileDescriptor = CInt

/// C-level port number in host byte order
public typealias UDPPort = in_port_t

/// A low-level UDP socket
public struct UDPSocket {
    public typealias EndPoint = (host: String, port: Int)
    let s: CFileDescriptor  ///< socket number
    let p: UDPPort          ///< UDP port in network byte order
}

extension UDPPort {
    /// Port number converted from host to  byte order
    var networkByteOrder: UDPPort { return htons(self) }
    /// Port number converted from network to host byte order
    var hostByteOrder: UDPPort { return ntohs(self) }
}

/// Error thrown by UDPSocket methods
///
/// - eof: remote end closed socket
/// - error: `errno` value in case of an error
public enum SocketError: Error {
    case eof
    case error(errno_t)
}

public extension UDPSocket {
    /// Create a UDP socket bound to a given port
    ///
    /// - Parameters:
    ///   - bind: binding IP address, "0.0.0.0" for any, or nil for transmitting broadcasts
    ///   - port: binding port in host byte order
    ///   - reuse: whether to allow reusing the port
    ///   - broadcast: whether this is a broadcast socket
    /// - Throws: errno if an error occurs
    public init(bind addr: String? = nil, port: UDPPort = 0, reuse: Bool = true, broadcast: Bool = true) throws {
        var inaddr = in_addr()
        if let srcaddr = addr {
            guard inet_aton(srcaddr, &inaddr) != 0 else {
                throw SocketError.error(errno) /// XXX: should try getaddrinfo()
            }
        } else {
            inaddr.s_addr = htonl(INADDR_BROADCAST)
        }
        s = socket(CInt(PF_INET), CInt(SOCK_DGRAM), CInt(IPPROTO_UDP))
        p = port.networkByteOrder
        guard s >= 0 else { throw SocketError.error(errno) }
        let sin_len = socklen_t(MemoryLayout<sockaddr_in>.size)
      #if os(Linux)
        var address = sockaddr_in(sin_family: sa_family_t(AF_INET), sin_port: p, sin_addr: inaddr, sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
      #else
        var address = sockaddr_in(sin_len: UInt8(sin_len), sin_family: sa_family_t(AF_INET), sin_port: p, sin_addr: inaddr, sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        do {
            var yes: CInt = 1
            setsockopt(s, CInt(SOL_SOCKET), CInt(SO_NOSIGPIPE), &yes, socklen_t(MemoryLayout<CInt>.size))
        }
      #endif
        if reuse {
            var yes: CInt = 1
            setsockopt(s, CInt(SOL_SOCKET), CInt(SO_REUSEADDR), &yes, socklen_t(MemoryLayout<CInt>.size))
        }
        if broadcast {
            var yes: CInt = 1
            setsockopt(s, CInt(SOL_SOCKET), CInt(SO_BROADCAST), &yes, socklen_t(MemoryLayout<CInt>.size))
        }
        guard addr != nil else { return }
        try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                guard bind(s, UnsafePointer<sockaddr>($0), sin_len) == 0 else {
                    throw SocketError.error(errno)
                }
            }
        }
    }

    /// Install a read event handler on the receiver
    ///
    /// - Parameters:
    ///   - q: dispatch queue to call `handler` on
    ///   - datagramSize: maximum size of the received UDP datagram
    ///   - handler: callback handlern when a packet is received
    /// - Returns: active dispatch read source (call `cancel` do shutdown and close socket)
    @discardableResult
    public func onRead(queue q: DispatchQueue = .main, datagramSize: Int = 4096, handler: @escaping (ArraySlice<UInt8>?, EndPoint?) -> Void) -> DispatchSourceRead {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: s, queue: q)
        readSource.setCancelHandler {
            let s = CInt(readSource.handle)
            shutdown(s, CInt(SHUT_RDWR))
            close(s)
        }
        readSource.setEventHandler {
            var sas = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            var packet = [UInt8](repeating: 0, count: datagramSize)
            let s = CInt(readSource.handle)
            let n = packet.withUnsafeMutableBytes { p in
                withUnsafeMutablePointer(to: &sas) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(s, p.baseAddress, datagramSize, 0, $0, &len)
                    }
                }
            }
            guard n >= 0 else { return handler(nil, nil) }
            let e = endpointFor(socketAddress: &sas)
            handler(packet.prefix(upTo: n), e)
        }
        readSource.resume()
        return readSource
    }

    /// Install a fixed-size datagram read event handler on the receiver
    ///
    /// - Parameters:
    ///   - q: dispatch queue to call `handler` on
    ///   - handler: callback handler when a packet is received
    /// - Returns: active dispatch read source (call `cancel` do shutdown and close socket)
    @discardableResult
    public func onRead<UDPPacket: NetworkByteOrderConvertible>(queue q: DispatchQueue = .main, handler: @escaping (UDPPacket, EndPoint?) -> Void) -> DispatchSourceRead {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: s, queue: q)
        readSource.setCancelHandler {
            let s = CInt(readSource.handle)
            shutdown(s, CInt(SHUT_RDWR))
            close(s)
        }
        readSource.setEventHandler {
            let data = UnsafeMutablePointer<UDPPacket>.allocate(capacity: 1)
            let size = MemoryLayout<UDPPacket>.size
            defer { data.deallocate(capacity: 1) }
            var sas = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let s = CInt(readSource.handle)
            while true {
                let n = withUnsafeMutablePointer(to: &sas) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(s, UnsafeMutableRawPointer(data), size, 0, $0, &len)
                    }
                }
                guard n > 0 else {
                    if errno == EAGAIN || errno == EINTR { continue }
                    return
                }
                guard n == size else {
                    return
                }
                break
            }
            let e = endpointFor(socketAddress: &sas)
            let p = UDPPacket(fromNetwork: data.pointee)
            handler(p, e)
        }
        readSource.resume()
        return readSource
    }

    /// Install a string-reader event handler on the receiver
    ///
    /// - Parameters:
    ///   - q: dispatch queue to call `handler` on
    ///   - datagramSize: maximum size of the received UDP datagram
    ///   - handler: callback handlern when a packet is received
    /// - Returns: active dispatch read source (call `cancel` do shutdown and close socket)
    @discardableResult
    public func onString(queue q: DispatchQueue = .main, datagramSize: Int = 4096, handler: @escaping (String, EndPoint?) -> Void) -> DispatchSourceRead {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: s, queue: q)
        readSource.setCancelHandler {
            let s = CInt(readSource.handle)
            shutdown(s, CInt(SHUT_RDWR))
            close(s)
        }
        readSource.setEventHandler {
            var sas = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let data = UnsafeMutablePointer<CChar>.allocate(capacity: datagramSize)
            defer { data.deallocate(capacity: datagramSize) }
            let s = CInt(readSource.handle)
            while true {
                let n = withUnsafeMutablePointer(to: &sas) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(s, UnsafeMutableRawPointer(data), datagramSize, 0, $0, &len)
                    }
                }
                guard n > 0 else {
                    if errno == EAGAIN || errno == EINTR { continue }
                    return
                }
                break
            }
            data[datagramSize-1] = 0
            let e = endpointFor(socketAddress: &sas)
            handler(String(cString: data), e)
        }
        readSource.resume()
        return readSource
    }

    /// Send the given data
    ///
    /// - Parameters:
    ///   - data: the data to send
    ///   - address: destination address (default: broadcast)
    ///   - port: destination port (default: same port as when socket was set up)
    /// - Returns: `true` iff successful
    @discardableResult
    public func send(data: Data, to destination: String? = nil, port p: UDPPort? = nil) -> Bool {
        var inaddr = in_addr()
        if let address = destination {
            guard inet_aton(address, &inaddr) != 0 else { return false }    /// XXX: should try getaddrinfo()
        } else {
            inaddr.s_addr = htonl(INADDR_BROADCAST)
        }
        let port = p?.networkByteOrder ?? self.p
        let sin_len = socklen_t(MemoryLayout<sockaddr_in>.size)
        #if os(Linux)
            var address = sockaddr_in(sin_family: sa_family_t(AF_INET), sin_port: port, sin_addr: inaddr, sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        #else
            var address = sockaddr_in(sin_len: UInt8(sin_len), sin_family: sa_family_t(AF_INET), sin_port: port, sin_addr: inaddr, sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        #endif
        let n = size_t(data.count)
        return data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Bool in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    sendto(s, UnsafeRawPointer(bytes), n, 0, addr, sin_len) == n
                }
            }
        }
    }

    /// Send the given text via UDP
    ///
    /// - Parameters:
    ///   - text: the text to send
    ///   - encoding: text encoding to use
    ///   - address: destination address (default: broadcast)
    ///   - port: destination port (default: same port as when socket was set up)
    /// - Returns: `true` iff successful
    @discardableResult
    public func send(_ text: String, using encoding: String.Encoding = .utf8, to destination: String? = nil, port p: UDPPort? = nil) -> Bool {
        guard let d = text.data(using: encoding) else { return false }
        return send(data: d, to: destination, port: p)
    }
}

/// Return the endpoint of a UDP datagram
///
/// - Parameter ptr: socket address received using `recv_from()`
/// - Returns: a host/port pair or nil if not resolvable
func endpointFor(socketAddress ptr: UnsafePointer<sockaddr_storage>) -> UDPSocket.EndPoint? {
    switch CInt(ptr.pointee.ss_family) {
    case AF_INET:
        let max = Int(INET_ADDRSTRLEN + 2)
        var sa = UnsafeRawPointer(ptr).load(as: sockaddr_in.self)
        var buffer = [CChar](repeating: 0, count: max)
        guard let host = inet_ntop(AF_INET, &sa.sin_addr, &buffer, socklen_t(max)) else {
            return nil
        }
        let port = Int(ntohs(UInt16(sa.sin_port)))
        return (String(cString: host), port)

    case AF_INET6:
        let max = Int(INET6_ADDRSTRLEN + 2)
        var sa = UnsafeRawPointer(ptr).load(as: sockaddr_in6.self)
        var buffer = [CChar](repeating: 0, count: max)
        guard let host = inet_ntop(AF_INET6, &sa.sin6_addr, &buffer, socklen_t(max)) else {
            return nil
        }
        let port = Int(ntohs(UInt16(sa.sin6_port)))
        return (String(cString: host), port)

    default:
        return nil
    }
}
