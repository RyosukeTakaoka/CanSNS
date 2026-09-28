import PhotosUI
import SwiftUI
import UIKit

/// 缶を納品する（＝投稿する）画面。1日に何本でも納品できる
struct DeliverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = CanDraft()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var showCamera = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    titleField
                    kindPicker
                    contentInput
                    moodPicker
                    patternPicker
                    Toggle(isOn: $draft.allowFridge) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("友達の冷蔵庫に入れてOK")
                                .font(.subheadline.bold())
                            Text("オフにすると、翌朝6:00の廃棄で友達の手元からは消えます")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .card()
                    deliverButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("納品する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPicked(newItem) }
            }
            .onChange(of: draft.kind) { _, _ in
                clearMedia()
            }
            .onChange(of: recorder.recordedFileName) { _, fileName in
                guard draft.kind == .voice else { return }
                draft.mediaFileName = fileName
                draft.mediaDuration = fileName == nil ? nil : recorder.recordedDuration
            }
            .onChange(of: draft.title) { _, newValue in
                if newValue.count > CanDraft.titleLimit {
                    draft.title = String(newValue.prefix(CanDraft.titleLimit))
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(
                    mode: draft.kind == .video ? .video : .photo,
                    onImage: { image in savePhoto(image) },
                    onVideo: { url in Task { await saveVideo(from: url) } }
                )
                .ignoresSafeArea()
            }
            .alert("納品できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("マイクが使えません", isPresented: $recorder.permissionDenied) {
                Button("OK") {}
            } message: {
                Text("設定アプリで CanSNS のマイクを許可してください")
            }
        }
    }

    // MARK: - プレビュー

    private var preview: some View {
        HStack(spacing: 18) {
            CanView(
                title: draft.title.isEmpty ? "商品名" : draft.title,
                mood: draft.mood,
                kind: draft.kind,
                pattern: draft.pattern,
                emoji: store.currentUser?.emoji ?? "🙂",
                width: 80
            )
            VStack(alignment: .leading, spacing: 8) {
                MoodStrip(mood: draft.mood, fontSize: 13)
                Text("タイトルがそのまま商品名になります。中身は21:00の開店まで、友達には見えません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - 入力欄

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("商品名（タイトル）", note: "\(draft.title.count)/\(CanDraft.titleLimit)")
            TextField("例：部活おわり", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("中身")
            Picker("中身", selection: $draft.kind) {
                ForEach(ContentKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            if draft.kind != .text && !store.canSendMedia {
                Label(CloudinaryError.notConfigured.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var contentInput: some View {
        switch draft.kind {
        case .text:
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("ひとこと", note: "\(draft.text.count)/\(CanDraft.textLimit)")
                TextField("今日あったこと、思ったこと", text: $draft.text, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: draft.text) { _, newValue in
                        if newValue.count > CanDraft.textLimit {
                            draft.text = String(newValue.prefix(CanDraft.textLimit))
                        }
                    }
            }
        case .photo, .video:
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(draft.kind == .photo ? "写真（1枚）" : "動画（\(Int(VideoUtil.maxDuration))秒まで）")
                mediaPreview
                HStack {
                    PhotosPicker(selection: $pickerItem,
                                 matching: draft.kind == .photo ? .images : .videos) {
                        Label("ライブラリから", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if CameraPicker.isAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("撮る", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                captionField
            }
        case .voice:
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("音声（\(Int(VoiceRecorder.maxDuration))秒まで）")
                voiceRecorderView
                captionField
            }
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if isLoading {
            ProgressView("読み込み中…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if draft.kind == .video, draft.mediaFileName != nil {
            Label("動画を入れました（\(Int((draft.mediaDuration ?? 0).rounded()))秒）", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(height: 110)
                .overlay(
                    Label("まだ入っていません", systemImage: draft.kind.symbol)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var voiceRecorderView: some View {
        HStack(spacing: 16) {
            Button {
                recorder.toggle()
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(recorder.isRecording ? Color.red : draft.mood.color, in: Circle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                if recorder.isRecording {
                    Text("録音中… \(Int(recorder.elapsed))秒")
                        .font(.headline.monospacedDigit())
                    ProgressView(value: min(recorder.elapsed, VoiceRecorder.maxDuration),
                                 total: VoiceRecorder.maxDuration)
                        .tint(.red)
                } else if let fileName = draft.mediaFileName {
                    Text("録音できました（\(Int((draft.mediaDuration ?? 0).rounded()))秒）")
                        .font(.headline)
                    VoicePlayerView(url: MediaStore.url(for: fileName), duration: draft.mediaDuration ?? 0,
                                    color: draft.mood.color)
                    Button("録り直す") { recorder.clear() }
                        .font(.caption)
                } else {
                    Text("ボタンを押して録音")
                        .font(.headline)
                    Text("もう一度押すと止まります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private var captionField: some View {
        TextField("ひとこと添える（任意・\(CanDraft.captionLimit)文字まで）", text: $draft.text, axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .onChange(of: draft.text) { _, newValue in
                if newValue.count > CanDraft.captionLimit {
                    draft.text = String(newValue.prefix(CanDraft.captionLimit))
                }
            }
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("今日の気分")
            HStack(spacing: 10) {
                ForEach(Mood.allCases) { mood in
                    Button {
                        draft.mood = mood
                        Haptics.impact(.light)
                    } label: {
                        VStack(spacing: 6) {
                            MoodStrip(mood: mood, fontSize: 13)
                            Text(mood.meaning)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(draft.mood == mood ? mood.color : .clear, lineWidth: 2.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("ラベルの柄")
            HStack(spacing: 14) {
                ForEach(LabelPattern.allCases) { pattern in
                    Button {
                        draft.pattern = pattern
                    } label: {
                        VStack(spacing: 4) {
                            CanView(title: "", mood: draft.mood, kind: draft.kind, pattern: pattern,
                                    emoji: "", width: 36)
                                .opacity(draft.pattern == pattern ? 1 : 0.55)
                            Text(pattern.label)
                                .font(.caption2)
                                .fontWeight(draft.pattern == pattern ? .bold : .regular)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deliverButton: some View {
        Button {
            deliver()
        } label: {
            Label("納品する（ガコン！）", systemImage: "shippingbox.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Theme.machineBody.gradient, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || recorder.isRecording)
    }

    private func sectionTitle(_ title: String, note: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
            Spacer()
            if let note {
                Text(note)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 処理

    private func deliver() {
        do {
            try store.deliver(draft)
            SoundPlayer.shared.play(.gakon)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearMedia() {
        pickerItem = nil
        previewImage = nil
        draft.mediaFileName = nil
        draft.mediaDuration = nil
        recorder.clear()
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }
        // 読み込み中に「中身」の種類を変えられたら、読み込んだものは使わない
        let kind = draft.kind
        do {
            switch kind {
            case .photo:
                if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   draft.kind == kind {
                    savePhoto(image)
                }
            case .video:
                if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    guard draft.kind == kind else {
                        try? FileManager.default.removeItem(at: movie.url)
                        return
                    }
                    await saveVideo(from: movie.url)
                }
            case .text, .voice:
                break
            }
        } catch {
            errorMessage = "読み込みに失敗しました：\(error.localizedDescription)"
        }
    }

    private func savePhoto(_ image: UIImage) {
        guard let data = ImageUtil.jpegData(from: image),
              let fileName = try? MediaStore.save(data, ext: "jpg") else {
            errorMessage = "写真を保存できませんでした"
            return
        }
        previewImage = image
        draft.mediaFileName = fileName
        draft.mediaDuration = nil
    }

    private func saveVideo(from url: URL) async {
        let duration = await VideoUtil.duration(of: url)
        guard duration <= VideoUtil.maxDuration + 0.5 else {
            errorMessage = "\(Int(VideoUtil.maxDuration))秒以内の動画にしてください（この動画は\(Int(duration))秒）"
            return
        }
        // 送る前に小さくする（失敗したら元の動画のまま）
        let compressed = await VideoUtil.compressed(url)
        let source = compressed ?? url
        defer {
            // 一時ファイルは片づける
            if let compressed { try? FileManager.default.removeItem(at: compressed) }
        }
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        guard let fileName = try? MediaStore.importFile(at: source, ext: ext) else {
            errorMessage = "動画を保存できませんでした"
            return
        }
        previewImage = nil
        draft.mediaFileName = fileName
        draft.mediaDuration = duration
    }
}
