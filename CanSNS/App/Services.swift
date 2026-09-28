import AVFoundation
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - メディアの保存

/// 写真・動画・音声を端末の Documents/Media に保存する
enum MediaStore {
    static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func newFileName(ext: String) -> String {
        "\(UUID().uuidString).\(ext)"
    }

    static func save(_ data: Data, ext: String) throws -> String {
        let name = newFileName(ext: ext)
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    static func importFile(at source: URL, ext: String) throws -> String {
        let name = newFileName(ext: ext)
        try FileManager.default.copyItem(at: source, to: url(for: name))
        return name
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum ImageUtil {
    /// 大きすぎる写真を縮小して JPEG にする
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1280) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

enum VideoUtil {
    static let maxDuration: Double = 15

    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let time = (try? await asset.load(.duration)) ?? .zero
        return time.seconds.isFinite ? time.seconds : 0
    }
}

/// PhotosPicker から動画を受け取るための型
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

// MARK: - 効果音と振動

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    var isEnabled = true
    private var players: [SoundEffect: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for effect in SoundEffect.allCases {
            let player = try? AVAudioPlayer(data: SoundSynth.wavData(for: effect))
            player?.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: SoundEffect) {
        guard isEnabled, let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }
}

enum Haptics {
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - 通知（開店・廃棄のお知らせ）

enum NotificationScheduler {
    static func requestAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted { schedule() }
        }
    }

    /// 毎日くり返すローカル通知を登録する（同じIDなので何度呼んでも上書きされるだけ）
    static func schedule() {
        let items: [(id: String, hour: Int, minute: Int, title: String, body: String)] = [
            ("reminder-deliver", 19, 30, "納品はおすみですか？", "21:00に自販機が開店します。今日の缶を納品しよう🥫"),
            ("reminder-open", 21, 0, "🌙 自販機が開店しました", "友達の今日を受け取りにいこう。ガコン！"),
            ("reminder-dispose", 5, 30, "まもなく廃棄", "6:00に缶が廃棄されます。残したい缶は冷蔵庫へ🧊"),
        ]
        let center = UNUserNotificationCenter.current()
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            var components = DateComponents()
            components.hour = item.hour
            components.minute = item.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}

// MARK: - 音声の録音と再生

/// 「音声」缶の録音（最大15秒）
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let maxDuration: TimeInterval = 15

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recordedFileName: String?
    @Published private(set) var recordedDuration: TimeInterval = 0
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.beginRecording()
                } else {
                    self.permissionDenied = true
                }
            }
        }
    }

    func stop() {
        recorder?.stop()
    }

    func clear() {
        recordedFileName = nil
        recordedDuration = 0
        elapsed = 0
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let fileName = MediaStore.newFileName(ext: "m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: MediaStore.url(for: fileName), settings: settings) else { return }
        recorder.delegate = self
        recorder.record(forDuration: Self.maxDuration)
        self.recorder = recorder
        pendingFileName = fileName
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            self.elapsed = recorder.currentTime
        }
    }

    private var pendingFileName: String?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
            self.isRecording = false
            if flag, let name = self.pendingFileName {
                self.recordedDuration = max(self.elapsed, 0.5)
                self.recordedFileName = name
            }
            self.pendingFileName = nil
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        }
    }
}

/// 音声缶の再生
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            finish(resetProgress: false)
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
        }
        guard let player else { return }
        player.play()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, player.duration > 0 else { return }
            self.progress = player.currentTime / player.duration
        }
    }

    func stop() {
        player?.stop()
        finish(resetProgress: true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.finish(resetProgress: true)
        }
    }

    private func finish(resetProgress: Bool) {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        if resetProgress {
            progress = 0
            player?.currentTime = 0
        }
    }
}

// MARK: - カメラ

/// カメラで写真または動画を撮る（シミュレーターではカメラが使えない）
struct CameraPicker: UIViewControllerRepresentable {
    enum Mode { case photo, video }

    var mode: Mode
    var onImage: (UIImage) -> Void = { _ in }
    var onVideo: (URL) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        switch mode {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
            picker.videoMaximumDuration = VideoUtil.maxDuration
            picker.videoQuality = .typeMedium
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else if let url = info[.mediaURL] as? URL {
                parent.onVideo(url)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
