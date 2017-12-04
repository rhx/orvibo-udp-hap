//
//  orvibo-udp-hap
//
//  Created by Rene Hexel on 25/11/2017.
//  Copyright © 2017 Rene Hexel. All rights reserved.
//
import Foundation
import Dispatch
import Channel
import HAP

enum AccessoryKind: String {
    case light
    case outlet
    case `switch`
}

let args = CommandLine.arguments
let cmd = args[0]                   ///< command name
var name = convert(cmd, using: basename)
var verbosity = 1                   ///< verbosity level
var port = 14443                    ///< UDP listen port
var outp = 14442                    ///< UDP transmit port
var host = "127.0.0.1"              ///< Controller host
var pin = "123-45-678"
var vendor = "Orvibo"
var type = "UDP Bridge"
var serial = "234"
var version = "1.0.0"
var kind = AccessoryKind.outlet

fileprivate func usage() -> Never {
    print("Usage: \(cmd) <options>")
    print("Options:")
    print("  -d                 print debug output")
    print("  -f <version>       firmware version [\(version)]")
    print("  -h <host>          host device [\(host)]")
    print("  -k <accessorykind> \(AccessoryKind.light.rawValue), \(AccessoryKind.outlet.rawValue), or \(AccessoryKind.switch.rawValue) [\(kind.rawValue)]")
    print("  -l <port>          listen on <port> instead of \(port)")
    print("  -m <manufacturer>  name of the manufacturer [\(vendor)]")
    print("  -n <name>          name of the HomeKit bridge [\(name)]")
    print("  -p <port>          broadcast to <port> instead of \(outp)")
    print("  -q                 turn off all non-critical logging output")
    print("  -s <SECRET_PIN>    HomeKit PIN for authentication [\(pin)]")
    print("  -S <serial>        Device serial number [\(serial)]")
    print("  -t <type>          name of the model/type [\(type)]")
    print("  -v                 increase logging verbosity\n")
    exit(EXIT_FAILURE)
}

while let result = get(options: "df:h:k:l:m:n:p:qs:S:t:v") {
    let option = result.0
    let arg = result.1
    switch option {
    case "d": verbosity = 9
    case "f": version = arg!
    case "h": host = arg!
    case "k": kind = AccessoryKind(rawValue: arg!)!
    case "l": if let p = Int(arg!) {
        port = p
    } else { usage() }
    case "m": vendor = arg!
    case "n": name = arg!
    case "p": if let p = Int(arg!) {
        outp = p
    } else { usage() }
    case "q": verbosity  = 0
    case "s": pin = arg!
    case "S": serial = arg!
    case "t": type = arg!
    case "v": verbosity += 1
    default:
        print("Unknown option \(option)!")
        usage()
    }
}

let fm = FileManager.default
let dbPath = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(name).path
let dbExists = fm.fileExists(atPath: dbPath)
let db: FileStorage
do {
    db = try FileStorage(path: dbPath)
} catch {
    fputs("Cannot open file storage at \(dbPath)\n", stderr)
    exit(EXIT_FAILURE)
}
if !dbExists { RunLoop.main.run(until: Date(timeIntervalSinceNow: 5)) }

let serviceInfo = Service.Info(name: name, manufacturer: vendor, model: type, serialNumber: serial, firmwareRevision: version)
let outlet: Accessory
switch kind {
case .light: outlet = Accessory.Lightbulb(info: serviceInfo)
case .outlet: outlet = Accessory.Outlet(info: serviceInfo)
case .switch: outlet = Accessory.Switch(info: serviceInfo)
}
let device = Device(bridgeInfo: serviceInfo, setupCode: pin, storage: db, accessories: [outlet])

var active = true
signal(SIGINT) { sig in
    DispatchQueue.main.async {
        active = false
        if verbosity > 0 {
            fputs("Caught signal \(sig) -- stopping!\n", stderr)
        }
    }
}

let udpStatus  = Channel<Substring>(capacity: 1)
let udpIn  = try UDPSocket(bind: "0.0.0.0", port: UDPPort(port))
let udpOut = try UDPSocket(port: UDPPort(outp))
let server = try Server(device: device, port: 0)
server.start()

func system(_ command: String, _ args: String...) {
    let process = Process.launchedProcess(launchPath: command, arguments: args)
    process.waitUntilExit()
}

func sendUDP(_ content: String) { udpOut.send(content, to: host) }

func toUDP(status value: Bool?) {
    let payload: String
    if let set = value { payload = set ? "on\n" : "off\n" }
    else { payload = "p\n" }
    if verbosity > 1 { print("Sending \(payload)", terminator: "") }
    sendUDP(payload)
}

func fromUDP(status: Bool?) {
    DispatchQueue.main.async {
        if verbosity > 0 { print("Status: \(String(describing: status))") }
        switch outlet {
        case let light as Accessory.Lightbulb: light.lightbulb.on.value = status
        case let outlet as Accessory.Outlet: outlet.outlet.on.value = status
        case let `switch` as Accessory.Switch: `switch`.switch.on.value = status
        default: return
        }
    }
}

func status() -> Bool? {
    switch outlet {
    case let light as Accessory.Lightbulb: return light.lightbulb.on.value
    case let outlet as Accessory.Outlet: return outlet.outlet.on.value
    case let `switch` as Accessory.Switch: return `switch`.switch.on.value
    default: return nil
    }
}

switch outlet {
case let light as Accessory.Lightbulb: light.lightbulb.on.onValueChange.append(toUDP)
case let outlet as Accessory.Outlet: outlet.outlet.on.onValueChange.append(toUDP)
case let `switch` as Accessory.Switch: `switch`.switch.on.onValueChange.append(toUDP)
default: print("Cannot subscribe to changes for unknown accessory type '\(kind)'")
}

var readQueue = DispatchQueue(label: "orvibo.udp.read")
let udpSource = udpIn.onString(queue: readQueue) { content, endPoint in
    let lines = content.split(separator: "\n")
    for line in lines {
        let lower = line.lowercased()
        if lower.starts(with: "on") { fromUDP(status: true) }
        else if lower.starts(with: "off") { fromUDP(status: false) }
    }
}

fromUDP(status: nil)
toUDP(status: nil)

let countDown = 60/2
var count = countDown
while active {
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    count -= 1
    guard count <= 0 else { continue }
    count = countDown
    guard let currentStatus = status() else {
        sendUDP("q\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
            toUDP(status: nil)
        }
        continue
    }
}

if verbosity > 2 { fputs("Stopping server.\n", stderr) }
server.stop()
if verbosity > 0 { fputs("Exiting.\n", stderr) }

