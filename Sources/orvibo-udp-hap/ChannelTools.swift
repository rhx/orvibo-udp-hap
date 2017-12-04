//
//  ChannelTools.swift
//  solarpoolheating-hapPackageDescription
//
//  Created by Rene Hexel on 26/11/17.
//  Copyright © 2017 Rene Hexel. All rights reserved.
//
import Foundation
import Channel

extension Channel {
    func purge(timeout t: DispatchTimeInterval = .milliseconds(500)) {
        while let line = receive(timeout: t) {
            print("Purging '\(line)'")
        }
    }
}
