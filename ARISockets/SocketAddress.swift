//
//  SocketAddress.swift
//  TestSwiftyCocoa
//
//  Created by Helge Heß on 6/12/14.
//  Copyright (c) 2014 Helge Hess. All rights reserved.
//

import Darwin
// import Darwin.POSIX.netinet.`in` - this doesn't seem to work
// import struct Darwin.POSIX.netinet.`in`.sockaddr_in - neither

let INADDR_ANY = in_addr(s_addr: 0)

func ==(lhs: in_addr, rhs: in_addr) -> Bool {
  return __uint32_t(lhs.s_addr) == __uint32_t(rhs.s_addr)
}

/**
 * in_addr represents an IPv4 address in Unix. We extend that a little bit
 * to increase it's usability :-)
 */
extension in_addr {

  init() {
    s_addr = INADDR_ANY.s_addr
  }
  
  init(string: String?) {
    if let s = string {
      if s.isEmpty {
        s_addr = INADDR_ANY.s_addr
      }
      else {
        var buf = INADDR_ANY // Swift wants some initialization
        
        // maybe only required on 10.10? crashes w/o forcing a copy
        var sc = s + ""
        sc.withCString { cs in inet_pton(AF_INET, cs, &buf) }
        s_addr = buf.s_addr
      }
    }
    else {
      s_addr = INADDR_ANY.s_addr
    }
  }
  
  var asString: String {
    if self == INADDR_ANY {
      return "*.*.*.*"
    }
    
    let len   = Int(INET_ADDRSTRLEN) + 2
    var buf   = CChar[](count: len, repeatedValue: 0)
    
    var selfCopy = self // &self doesn't work, because it can be const?
    let cs = inet_ntop(AF_INET, &selfCopy, &buf, socklen_t(len))
    
    return String.fromCString(cs)
  }
  
}

/*
 * FIXME: This gives "Invalid redeclaration of '=='". Maybe Swift somehow
 *        aliases the simple struct to an Int32?
func == (lhs: in_addr, rhs: in_addr) -> Bool {
  return lhs.s_addr == rhs.s_addr
}
*/
extension in_addr : Equatable, Hashable {
  
  var hashValue: Int {
    // Knuth?
    return Int(UInt32(s_addr) * 2654435761 % (2^32))
  }
  
}

extension in_addr: StringLiteralConvertible {
  // this allows you to do: let addr : in_addr = "192.168.0.1"
  
  static func convertFromStringLiteral(value: StringLiteralType) -> in_addr {
    return in_addr(string: value)
  }
  
  static func convertFromExtendedGraphemeClusterLiteral
    (value: ExtendedGraphemeClusterType) -> in_addr
  {
    return in_addr(string: value)
  }
}

extension in_addr: Printable {
  
  var description: String {
    return asString
  }
    
}


protocol SocketAddress {
  
  class var domain: CInt { get }
  
  init() // create empty address, to be filled by eg getsockname()
  
  var len: __uint8_t { get }
}

extension sockaddr_in: SocketAddress {
  
  static var domain = AF_INET // if you make this a let, swiftc segfaults
  static var size = __uint8_t(sizeof(sockaddr_in)) // how to refer to self?
  
  init() {
    sin_len    = sockaddr_in.size
    sin_family = sa_family_t(sockaddr_in.domain)
    sin_port   = 0
    sin_addr   = INADDR_ANY
    sin_zero   = (0,0,0,0,0,0,0,0)
  }
  
  init(address: in_addr = INADDR_ANY, port: Int?) {
    self.init()
    
    sin_port = port ? in_port_t(htons(CUnsignedShort(port!))) : 0
    sin_addr = address
  }
  
  init(address: String?, port: Int?) {
    let isWildcard = address ? (address! == "*" || address! == "*.*.*.*"):true;
    let ipv4       = isWildcard ? INADDR_ANY : in_addr(string: address)
    self.init(address: ipv4, port: port)
  }
  
  init(string: String?) {
    if let s = string {
      if s.isEmpty {
        self.init(address: INADDR_ANY, port: nil)
      }
      else {
        // split string at colon
        let comps = split(s, { $0 == ":"}, maxSplit: 1)
        if comps.count == 2 {
          self.init(address: comps[0], port: comps[1].toInt())
        }
        else {
          assert(comps.count == 1)
          let c1 = comps[0]
          let isWildcard = (c1 == "*" || c1 == "*.*.*.*")
          if isWildcard {
            self.init(address: nil, port: nil)
          }
          else if let port = c1.toInt() { // it's a number
            self.init(address: nil, port: port)
          }
          else { // it's a host
            self.init(address: c1, port: nil)
          }
        }
      }
    }
    else {
      self.init(address: INADDR_ANY, port: nil)
    }
  }
  
  var port: Int { // should we make that optional and use wildcard as nil?
    get {
      return Int(ntohs(sin_port))
    }
    set {
      sin_port = in_port_t(htons(CUnsignedShort(newValue)))
    }
  }
  
  var address: in_addr {
    return sin_addr
  }
  
  var isWildcardPort:    Bool { return sin_port == 0 }
  var isWildcardAddress: Bool { return sin_addr == INADDR_ANY }
  
  var len: __uint8_t { return sockaddr_in.size }

  var asString: String {
    let addr = address.asString
    return isWildcardPort ? addr : "\(addr):\(port)"
  }
}

func == (lhs: sockaddr_in, rhs: sockaddr_in) -> Bool {
  return (lhs.sin_addr.s_addr == rhs.sin_addr.s_addr)
      && (lhs.sin_port        == rhs.sin_port)
}

extension sockaddr_in: Equatable, Hashable {
  
  var hashValue: Int {
    return sin_addr.hashValue + sin_port.hashValue
  }
  
}

/**
 * This allows you to do: let addr : sockaddr_in = "192.168.0.1:80"
 *
 * Adding an IntLiteralConvertible seems a bit too weird and ambigiuous to me.
 *
 * Note: this does NOT work:
 *   let s : sockaddr_in = "*:\(port)"
 * it requires:
 *   StringInterpolationConvertible
 */
extension sockaddr_in: StringLiteralConvertible {
  
  static func convertFromStringLiteral(value:StringLiteralType) -> sockaddr_in {
    return sockaddr_in(string: value)
  }
  
  static func convertFromExtendedGraphemeClusterLiteral
    (value: ExtendedGraphemeClusterType) -> sockaddr_in
  {
    return sockaddr_in(string: value)
  }
}

extension sockaddr_in: Printable {
  
  var description: String {
    return asString
  }
  
}

extension sockaddr_in6: SocketAddress {
  
  static var domain = AF_INET6
  static var size   = __uint8_t(sizeof(sockaddr_in6))
  
  init() {
    sin6_len      = sockaddr_in6.size
    sin6_family   = sa_family_t(sockaddr_in.domain)
    sin6_port     = 0
    sin6_flowinfo = 0
    sin6_addr     = in6addr_any
    sin6_scope_id = 0
  }
  
  var port: Int {
    get {
      return Int(ntohs(sin6_port))
    }
    set {
      sin6_port = in_port_t(htons(CUnsignedShort(newValue)))
    }
  }
  
  var isWildcardPort: Bool { return sin6_port == 0 }
  
  var len: __uint8_t { return sockaddr_in6.size }
}

extension sockaddr_un: SocketAddress {
  // TBD: sockaddr_un would be interesting as the size of the structure is
  //      technically dynamic (embedded string)
  
  static var domain = AF_UNIX
  static var size   = __uint8_t(sizeof(sockaddr_un)) // CAREFUL
  
  init() {
    sun_len    = sockaddr_un.size // CAREFUL - kinda wrong
    sun_family = sa_family_t(sockaddr_un.domain)
    
    // Autsch!
    sun_path   = (
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0
    );
  }
  
  var len: __uint8_t {
    // FIXME?: this is wrong. It needs to be the base size + string length in
    //         the buffer
    return sockaddr_un.size
  }
}
