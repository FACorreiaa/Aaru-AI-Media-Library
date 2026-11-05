import AVFoundation
import Foundation

/// Records one spoken question to a temp file. Audio is never kept: the file is deleted on
/// `stop()` and `discard()`, sent or not.
@MainActor
final class VoiceRecorder: NSObject {
    struct Recording {
        let data: Data
        let seconds: Double
    }

    private static let maxSeconds: TimeInterval = 60
    private static let minSeconds: TimeInterval = 0.3

    /// Called once if the system takes the mic away (a call). The recording is already discarded.
    var onInterrupted: (@MainActor () -> Void)?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startedAt: ContinuousClock.Instant?
    #if os(iOS)
        private var interruptionTask: Task<Void, Never>?
    #endif

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        discard()
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true)
        #endif
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aaru-question-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            fileURL = url
            self.recorder = recorder
            guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maxSeconds) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            discard()
            throw error
        }
        startedAt = ContinuousClock.now
        #if os(iOS)
            observeInterruptions()
        #endif
    }

    /// Latest level in dBFS; nil while not recording.
    func power() -> Float? {
        guard let recorder, recorder.isRecording else { return nil }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    /// The audio, or nil under 0.3 s. Deletes the file either way.
    func stop() -> Recording? {
        guard let recorder, let url = fileURL, let startedAt else {
            discard()
            return nil
        }
        let elapsed = (ContinuousClock.now - startedAt).components
        let seconds = min(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, Self.maxSeconds)
        recorder.stop()
        let data = try? Data(contentsOf: url)
        discard()
        guard seconds >= Self.minSeconds, let data, !data.isEmpty else { return nil }
        return Recording(data: data, seconds: seconds)
    }

    func discard() {
        recorder?.stop()
        recorder = nil
        startedAt = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        #if os(iOS)
            interruptionTask?.cancel()
            interruptionTask = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(iOS)
        private func observeInterruptions() {
            interruptionTask?.cancel()
            interruptionTask = Task { [weak self] in
                let began = NotificationCenter.default
                    .notifications(named: AVAudioSession.interruptionNotification)
                    .compactMap { note -> Bool? in
                        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                        return raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began ? true : nil
                    }
                for await _ in began {
                    guard let self else { return }
                    self.interrupted()
                    return
                }
            }
        }

        private func interrupted() {
            let callback = onInterrupted
            discard()
            callback?()
        }
    #endif
}
