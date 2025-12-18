//
//  DeviceConnectionContext.swift
//  StikJIT
//
//  Created by Stephen.
//

import Foundation

enum DeviceConnectionContext {
    static var isUsingExternalDevice: Bool {
        DeviceLibraryStore.shared.isUsingExternalDevice
    }
    
    static var requiresLoopbackVPN: Bool {
        false
    }
    
    static var targetIPAddress: String {
        if let device = DeviceLibraryStore.shared.activeDevice {
            return device.ipAddress
        }
        return "127.0.0.1"
    }
}
