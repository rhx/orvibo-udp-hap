# orvibo-udp-hap

A simple HAP (HomeKit Automation Protocol) bridge for the Orvibo S20 Wifi socket in Swift.

To make this work you need to install the [orvibo](https://github.com/rhx/orvibo) command line tool and UDP bridge first and run it on the same host using
```
orvibo -b14443 -u14442 -t2 ac:cf:23:24:25:26
```
(replacing `ac:cf:23:24:25:26` with the MAC address of your orvibo socket).

## Building

### Linux

```
sudo apt install openssl libssl-dev libsodium-dev libcurl4-openssl-dev
swift build -c release
```

### macOS

```
brew install libsodium
swift build -c release
```

To build using Xcode, use

```
brew install libsodium
swift package generate-xcodeproj
open orvibo-udp-hap.xcodeproj
```

## Usage
```
orvibo-udp-hap <options>
Options:
  -d                 print debug output
  -f <version>       firmware version [1.0.0]
  -h <host>          host device [127.0.0.1]
  -k <accessorykind> light, outlet, or switch
  -l <port>          listen on <port> instead of 14443
  -m <manufacturer>  name of the manufacturer [Orvibo]
  -n <name>          name of the HomeKit bridge [orvibo-udp-hap]
  -p <port>          broadcast to <port> instead of 14442
  -q                 turn off all non-critical logging output
  -s <SECRET_PIN>    HomeKit PIN for authentication [123-45-678]
  -S <serial>        Device serial number [234]
  -t <type>          name of the model/type [UDP Bridge]
  -v                 increase logging verbosity
```
The default pin is `123-45-678`.
