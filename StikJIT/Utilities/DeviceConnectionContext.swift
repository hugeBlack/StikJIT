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
        !isUsingExternalDevice
    }
    
    static var targetIPAddress: String {
        if let device = DeviceLibraryStore.shared.activeDevice {
            return device.ipAddress
        }
        return UserDefaults.standard.string(forKey: "TunnelDeviceIP") ?? "10.7.0.2"
    }
}
