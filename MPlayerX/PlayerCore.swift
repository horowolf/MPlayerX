/*
 * MPlayerX - PlayerCore.swift
 */

import Cocoa

private let kPlayerCoreTermNormal: Int32 = 0

@objc protocol PlayerCoreDelegate: NSObjectProtocol {
    func playerCore(_ player: Any, hasTerminated byForce: Bool)		/**< notifies that the playback task has terminated */
    func playerCore(_ player: Any, outputAvailable outData: Data)		/**< output is available */
    func playerCore(_ player: Any, errorHappened errData: Data)		/**< error output is available */
}

@objc(PlayerCore)
class PlayerCore: NSObject {
    @objc weak var delegate: PlayerCoreDelegate?

    private var task: Process?
    private let runningModes: [RunLoop.Mode] = [.default, .modalPanel, .eventTracking]

    deinit {
        delegate = nil
        terminate()
    }

    @objc func terminate() {
        guard let currentTask = task else { return }
        task = nil

        if currentTask.isRunning {
            currentTask.terminate()
            currentTask.waitUntilExit()
        }
    }

    @objc(playMedia:withExec:withParams:)
    func playMedia(_ moviePath: String?, withExec execPath: String?, withParams params: [Any]?) -> Bool {
        guard let moviePath = moviePath, let execPath = execPath else { return false }

        terminate()

        let newTask = Process()
        newTask.standardInput = Pipe()
        newTask.standardOutput = Pipe()
        newTask.standardError = Pipe()
        newTask.launchPath = execPath

        let stringParams = params?.compactMap { $0 as? String } ?? []
        newTask.arguments = stringParams + [moviePath]

        MPLogString((newTask.arguments ?? []).joined(separator: "\n"))

        var env = ProcessInfo.processInfo.environment
        env["DYLD_BIND_AT_LAUNCH"] = "1"
        env["TERM"] = "xterm"
        env.removeValue(forKey: "MPLAYER_HOME")
        env.removeValue(forKey: "HOME")
        newTask.environment = env
        newTask.currentDirectoryPath = (execPath as NSString).deletingLastPathComponent

        task = newTask

        let outputHandle = (newTask.standardOutput as? Pipe)?.fileHandleForReading
        let errorHandle = (newTask.standardError as? Pipe)?.fileHandleForReading

        if let outputHandle = outputHandle {
            NotificationCenter.default.addObserver(self, selector: #selector(readOutput(_:)), name: FileHandle.readCompletionNotification, object: outputHandle)
        }
        if let errorHandle = errorHandle {
            NotificationCenter.default.addObserver(self, selector: #selector(readError(_:)), name: FileHandle.readCompletionNotification, object: errorHandle)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(taskHasTerminated(_:)), name: Process.didTerminateNotification, object: newTask)

        outputHandle?.readInBackgroundAndNotify(forModes: runningModes)
        errorHandle?.readInBackgroundAndNotify(forModes: runningModes)

        newTask.launch()
        return true
    }

    @objc(sendStringCommand:)
    func sendStringCommand(_ cmd: String?) -> Bool {
        guard let cmd = cmd,
              let currentTask = task,
              currentTask.isRunning,
              let inputPipe = currentTask.standardInput as? Pipe,
              let data = cmd.data(using: .utf8) else {
            return false
        }

        inputPipe.fileHandleForWriting.write(data)
        return true
    }

    @objc private func readOutput(_ notification: Notification) {
        guard let currentTask = task, currentTask.isRunning else { return }
        let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data ?? Data()

        if !data.isEmpty {
            delegate?.playerCore(self, outputAvailable: data)
        }

        (currentTask.standardOutput as? Pipe)?.fileHandleForReading.readInBackgroundAndNotify(forModes: runningModes)
    }

    @objc private func readError(_ notification: Notification) {
        guard let currentTask = task, currentTask.isRunning else { return }
        let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data ?? Data()

        if !data.isEmpty {
            delegate?.playerCore(self, errorHappened: data)
        }

        (currentTask.standardError as? Pipe)?.fileHandleForReading.readInBackgroundAndNotify(forModes: runningModes)
    }

    @objc private func taskHasTerminated(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        let process = notification.object as? Process
        delegate?.playerCore(self, hasTerminated: (process?.terminationStatus ?? kPlayerCoreTermNormal) != kPlayerCoreTermNormal)
    }
}
