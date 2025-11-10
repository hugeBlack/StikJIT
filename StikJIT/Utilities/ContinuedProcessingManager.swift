//
//  ContinuedProcessingManager.swift
//  StikJIT
//
//  Created by Codex on 11/20/24.
//

import Foundation
import BackgroundTasks

final class ContinuedProcessingManager {
    static let shared = ContinuedProcessingManager()
    private let handler: ContinuedProcessingHandling
    
    private init() {
        if #available(iOS 26.0, *) {
            handler = ModernContinuedProcessingHandler()
        } else {
            handler = NoopContinuedProcessingHandler()
        }
    }
    
    var isSupported: Bool { handler.isSupported }
    
    func configureIfNeeded() {
        handler.configureIfNeeded()
    }
    
    func begin(title: String, subtitle: String) {
        handler.begin(title: title, subtitle: subtitle)
    }
    
    func updateProgress(_ fraction: Double) {
        handler.updateProgress(fraction)
    }
    
    func finish(success: Bool) {
        handler.finish(success: success)
    }
}

private protocol ContinuedProcessingHandling: AnyObject {
    var isSupported: Bool { get }
    func configureIfNeeded()
    func begin(title: String, subtitle: String)
    func updateProgress(_ fraction: Double)
    func finish(success: Bool)
}

private final class NoopContinuedProcessingHandler: ContinuedProcessingHandling {
    var isSupported: Bool { false }
    func configureIfNeeded() {}
    func begin(title: String, subtitle: String) {}
    func updateProgress(_ fraction: Double) {}
    func finish(success: Bool) {}
}

@available(iOS 26.0, *)
private final class ModernContinuedProcessingHandler: ContinuedProcessingHandling {
    private let scheduler = BGTaskScheduler.shared
    private let taskIdentifier: String
    private var didRegister = false
    private var activeTask: BGContinuedProcessingTask?
    private let queue = DispatchQueue(label: "com.stikdebug.continuedProcessing",
                                      qos: .utility)
    private var pendingMetadata: (title: String, subtitle: String)?
    
    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.stik.sj"
        taskIdentifier = "\(bundleID).continuedProcessingTask.script"
    }
    
    var isSupported: Bool { true }
    
    func configureIfNeeded() {
        guard !didRegister else { return }
        scheduler.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(task: continuedTask)
        }
        didRegister = true
    }
    
    func begin(title: String, subtitle: String) {
        guard UserDefaults.standard.bool(forKey: UserDefaults.Keys.enableContinuedProcessing) else { return }
        configureIfNeeded()
        var reserved = false
        queue.sync {
            if activeTask == nil && pendingMetadata == nil {
                pendingMetadata = (title: title, subtitle: subtitle)
                reserved = true
            }
        }
        guard reserved else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: taskIdentifier,
                                                       title: title,
                                                       subtitle: subtitle)
        request.strategy = .queue
        do {
            try scheduler.submit(request)
            LogManager.shared.addInfoLog("Requested continued processing: \(title)")
        } catch {
            LogManager.shared.addWarningLog("Unable to request continued processing: \(error.localizedDescription)")
            queue.async { [weak self] in
                self?.pendingMetadata = nil
            }
        }
    }
    
    func updateProgress(_ fraction: Double) {
        queue.async { [weak self] in
            guard let task = self?.activeTask else { return }
            let clamped = max(0.0, min(1.0, fraction))
            task.progress.totalUnitCount = max(task.progress.totalUnitCount, 100)
            task.progress.completedUnitCount = Int64(Double(task.progress.totalUnitCount) * clamped)
        }
    }
    
    func finish(success: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if let task = self.activeTask {
                task.progress.completedUnitCount = task.progress.totalUnitCount
                task.setTaskCompleted(success: success)
                self.activeTask = nil
            } else if pendingMetadata != nil {
                scheduler.cancel(taskRequestWithIdentifier: taskIdentifier)
            }
            pendingMetadata = nil
        }
    }

    private func handle(task: BGContinuedProcessingTask) {
        queue.async { [weak self] in
            guard let self else { return }
            activeTask = task
            if let metadata = pendingMetadata {
                task.updateTitle(metadata.title, subtitle: metadata.subtitle)
            }
            if task.progress.totalUnitCount == 0 {
                task.progress.totalUnitCount = 100
            }
            task.progress.completedUnitCount = 1
            task.expirationHandler = { [weak self] in
                self?.handleExpiration()
            }
        }
    }
    
    private func handleExpiration() {
        LogManager.shared.addWarningLog("Continued processing expired early")
        finish(success: false)
    }
}
