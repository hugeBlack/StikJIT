//
//  mountDDI.swift
//  StikJIT
//
//  Created by Stossy11 on 29/03/2025.
//

import Foundation

typealias IdevicePairingFile = OpaquePointer
typealias TcpProviderHandle = OpaquePointer
typealias CoreDeviceProxyHandle = OpaquePointer
typealias AdapterHandle = OpaquePointer
typealias ImageMounterHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
    MountingProgress.shared.progressCallback(progress: progress, total: total, context: context)
}

func isMounted() -> Bool {
    if DeviceConnectionContext.requiresLoopbackVPN {
        guard TunnelManager.shared.tunnelStatus == .connected else {
            return false
        }
    }
    
    do {
        let result = try JITEnableContext.shared.getMountedDeviceCount()
        return result > 0
    } catch {
        print("Error while getMountedDeviceCount \(error)")
        return false
    }
}

func mountPersonalDDI(imagePath: String, trustcachePath: String, manifestPath: String) -> Int {
    print("Mounting \(imagePath) \(trustcachePath) \(manifestPath)")
    
    do {
        try JITEnableContext.shared.mountPersonalDDI(withImagePath: imagePath, trustcachePath: trustcachePath, manifestPath: manifestPath)
    } catch {
        print("Failed to mount ddi: \(error)")
        return (error as NSError).code
    }
    return 0
}
