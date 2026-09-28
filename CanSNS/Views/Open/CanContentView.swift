import AVKit
import SwiftUI
import UIKit

/// 缶の中身の画面（開けたあと・自分の缶・冷蔵庫から見るときに使う）
struct CanContentView: View {
    let can: CanPost
    var justOpened: Bool = false
    var isWin: Bool = false

    @Environment(AppStore.self) private var store
    @State private var showStraw = false
    @State private var showLetter = false
    @State private var toast: String?

    private var me: String { store.currentUserID ?? "" }
    private var isAuthor: Bool { can.authorID == me }
    private var isDisposed: Bool { store.db.isDisposed(can, today: store.today) }
    private var author: UserProfile? { store.user(can.authorID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if isWin {
                    Text("🎉 ルーレットあたり！今日はラッキーな1本")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
                CanBodyView(can: can)
                if !isAuthor {
                    if isDisposed {
                        Label("この缶は廃棄済みです（冷蔵庫で保存中）", systemImage: "refrigerator")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        reactionSection
                        actionSection
                    }
                } else {
                    AuthorSummaryView(can: can)
                }
                IngredientsLabel(can: can, authorName: author?.name ?? "だれか", clock: store.clock)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(can.title)
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .sheet(isPresented: $showStraw) {
            NavigationStack {
                StrawThreadView(can: can, threadUserID: me)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLetter) {
            LetterSheet(can: can)
                .presentationDetents([.medium])
        }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CanView(can: can, emoji: author?.emoji ?? "🙂", width: 58, tabOpen: true, showsKind: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(can.title)
                    .font(.title2.bold())
                Text("\(author?.emoji ?? "") \(author?.name ?? "だれか")・\(DateText.monthDayTime(can.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    MoodStrip(mood: can.mood, fontSize: 12)
                    Text(can.mood.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - リアクション

    private var reactionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("リアクション")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ReactionKind.allCases) { kind in
                    let selected = store.db.hasReacted(canID: can.id, userID: me, kind: kind)
                    Button {
                        store.toggleReaction(kind, on: can)
                        SoundPlayer.shared.play(.tick)
                        Haptics.impact(.light)
                    } label: {
                        VStack(spacing: 4) {
                            Text(kind.emoji)
                                .font(.title2)
                            Text(kind.label)
                                .font(.subheadline.bold())
                            Text(kind.meaning)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? can.mood.color.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selected ? can.mood.color : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - ストロー・手紙・冷蔵庫

    private var actionSection: some View {
        VStack(spacing: 10) {
            actionButton(title: "ストローを差す", subtitle: "投稿者と1対1で返信", systemImage: "arrow.up.right") {
                showStraw = true
            }
            let sentLetter = store.db.letter(canID: can.id, from: me)
            actionButton(title: sentLetter == nil ? "返却口に手紙" : "手紙を入れました",
                         subtitle: sentLetter?.text ?? "投稿者だけに届く短いメッセージ",
                         systemImage: "envelope.fill") {
                showLetter = true
            }
            fridgeButton
        }
    }

    @ViewBuilder
    private var fridgeButton: some View {
        if store.db.isInFridge(canID: can.id, ownerID: me) {
            actionButton(title: "冷蔵庫に入っています", subtitle: "廃棄されたあとも見られます",
                         systemImage: "checkmark.circle.fill") {}
                .disabled(true)
        } else if !can.allowFridge {
            actionButton(title: "持ち帰りできない缶です", subtitle: "投稿者が冷蔵庫への保存をオフにしています",
                         systemImage: "nosign") {}
                .disabled(true)
        } else {
            actionButton(title: "冷蔵庫に入れる", subtitle: "翌朝6:00の廃棄後も残せます（投稿者に通知されます）",
                         systemImage: "refrigerator.fill") {
                do {
                    try store.saveToFridge(can)
                    Haptics.success()
                    toast = "冷蔵庫に入れました🧊"
                } catch {
                    toast = error.localizedDescription
                }
            }
        }
    }

    private func actionButton(title: String, subtitle: String, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(can.mood.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 中身の表示

struct CanBodyView: View {
    let can: CanPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch can.kind {
            case .photo:
                if let name = can.mediaFileName,
                   let image = UIImage(contentsOfFile: MediaStore.url(for: name).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    missingMedia
                }
            case .video:
                if let name = can.mediaFileName {
                    VideoContentView(url: MediaStore.url(for: name))
                } else {
                    missingMedia
                }
            case .voice:
                if let name = can.mediaFileName {
                    VoicePlayerView(url: MediaStore.url(for: name), duration: can.mediaDuration ?? 0,
                                    color: can.mood.color)
                } else {
                    missingMedia
                }
            case .text:
                EmptyView()
            }

            if let text = can.text {
                Text(text)
                    .font(can.kind == .text ? .title3.weight(.semibold) : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(can.kind == .text ? 22 : 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(can.kind == .text ? can.mood.color.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                    )
            }
        }
    }

    private var missingMedia: some View {
        Label("中身のファイルが見つかりません", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
    }
}

struct VideoContentView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxHeight: 460)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: url)
                }
                player?.play()
            }
            .onDisappear {
                player?.pause()
            }
    }
}

struct VoicePlayerView: View {
    let url: URL
    let duration: Double
    let color: Color
    @StateObject private var playback = AudioPlayback()

    var body: some View {
        HStack(spacing: 14) {
            Button {
                playback.toggle(url: url)
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(color, in: Circle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                // 波形っぽい棒（再生位置まで色がつく）
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<28, id: \.self) { index in
                        let height = CGFloat(8 + (index * 13) % 22)
                        Capsule()
                            .fill(Double(index) / 28 < playback.progress ? color : Color.secondary.opacity(0.3))
                            .frame(width: 4, height: height)
                    }
                }
                Text("\(Int(duration.rounded()))秒の音声")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .onDisappear { playback.stop() }
    }
}

// MARK: - 成分表示

/// 缶の「成分表示」欄を、投稿の情報を見せる場所として使う
struct IngredientsLabel: View {
    let can: CanPost
    let authorName: String
    let clock: BusinessClock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("成分表示")
                .font(.caption.bold())
                .padding(.bottom, 6)
            Divider().overlay(Color.black)
            row("名称", "\(can.kind.label)缶")
            row("原材料名", ingredients)
            row("内容量", can.contentSummary)
            row("製造者", authorName)
            row("製造時刻", DateText.monthDayTime(can.createdAt))
            row("賞味期限", "\(DateText.monthDayTime(clock.disposalTime(of: can.businessDay)))（自販機からは廃棄）")
            row("保存方法", can.allowFridge ? "友達の冷蔵庫で保存できます" : "持ち帰り不可（この自販機限定）")
        }
        .font(.caption)
        .foregroundStyle(Color.black)
        .padding(12)
        .background(Theme.paper)
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
    }

    private var ingredients: String {
        var items = [can.kind.label]
        if can.kind != .text, can.text != nil { items.append("ひとこと") }
        items.append("\(can.mood.stripText)成分")
        return items.joined(separator: "、")
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(title)
                    .fontWeight(.bold)
                    .frame(width: 64, alignment: .leading)
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 5)
            Divider().overlay(Color.black.opacity(0.4))
        }
    }
}

// MARK: - 投稿者から見た反応のまとめ

struct AuthorSummaryView: View {
    let can: CanPost
    @Environment(AppStore.self) private var store

    var body: some View {
        let openings = store.db.openings(of: can.id)
        let reactions = store.db.reactions(of: can.id)
        let letters = store.db.letters(of: can.id)
        let threads = store.db.strawThreadUsers(canID: can.id)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("開けた人（\(openings.count)人）")
                    .font(.headline)
                if openings.isEmpty {
                    Text("まだ誰も開けていません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(openings) { opening in
                        HStack {
                            Text(store.user(opening.userID)?.emoji ?? "🙂")
                            Text(store.user(opening.userID)?.name ?? "だれか")
                                .font(.subheadline)
                            Spacer()
                            Text(DateText.time(opening.openedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .card()

            if !reactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("リアクション")
                        .font(.headline)
                    ForEach(ReactionKind.allCases) { kind in
                        let names = reactions.filter { $0.kind == kind }.compactMap { store.user($0.userID)?.name }
                        if !names.isEmpty {
                            HStack(alignment: .top) {
                                Text("\(kind.emoji) \(kind.label)")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(names.joined(separator: "、"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                .card()
            }

            if !letters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("返却口の手紙")
                        .font(.headline)
                    ForEach(letters) { letter in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("✉️ \(store.user(letter.fromID)?.name ?? "だれか")より")
                                .font(.caption.bold())
                            Text(letter.text)
                                .font(.subheadline)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .card()
            }

            if !threads.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ストロー（1対1の返信）")
                        .font(.headline)
                    ForEach(threads, id: \.self) { userID in
                        NavigationLink {
                            StrawThreadView(can: can, threadUserID: userID)
                        } label: {
                            HStack {
                                Text(store.user(userID)?.emoji ?? "🙂")
                                Text(store.user(userID)?.name ?? "だれか")
                                Spacer()
                                Text(store.db.strawMessages(canID: can.id, threadUserID: userID).last?.text ?? "")
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
        }
    }
}

// MARK: - ストロー（1対1の返信）

struct StrawThreadView: View {
    let can: CanPost
    /// 投稿者ではない側のユーザー
    let threadUserID: String

    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        let messages = store.db.strawMessages(canID: can.id, threadUserID: threadUserID)
        let me = store.currentUserID
        let partnerID = me == can.authorID ? threadUserID : can.authorID

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    Text("🥤 \(store.user(partnerID)?.name ?? "だれか")とあなただけが見られます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    ForEach(messages) { message in
                        let mine = message.senderID == me
                        HStack {
                            if mine { Spacer(minLength: 40) }
                            Text(message.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .foregroundStyle(mine ? Color.white : Color.primary)
                                .background(mine ? can.mood.color : Color(.secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            if !mine { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding()
            }
            if store.db.isDisposed(can, today: store.today) {
                Text("この缶は廃棄されたので、返信はできません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                HStack {
                    TextField("ストローでひとこと（\(StrawMessage.textLimit)文字まで）", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .padding(10)
                            .foregroundStyle(.white)
                            .background(can.mood.color, in: Circle())
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
        .navigationTitle("ストロー")
        .navigationBarTitleDisplayMode(.inline)
        .alert("送れませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func send() {
        do {
            try store.sendStraw(on: can, threadUserID: threadUserID, text: text)
            text = ""
            SoundPlayer.shared.play(.tick)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 返却口に手紙

struct LetterSheet: View {
    let can: CanPost
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("✉️ 返却口に手紙")
                .font(.title3.bold())
            Text("投稿者だけに届く短いメッセージです。1つの缶に1通だけ入れられます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let letter = store.db.letter(canID: can.id, from: store.currentUserID ?? "") {
                Text(letter.text)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                Label("投函ずみ", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                TextField("ひとこと（\(Letter.textLimit)文字まで）", text: $text, axis: .vertical)
                    .lineLimit(2...3)
                    .padding()
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: text) { _, newValue in
                        if newValue.count > Letter.textLimit {
                            text = String(newValue.prefix(Letter.textLimit))
                        }
                    }
                HStack {
                    Text("\(text.count)/\(Letter.textLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("返却口に入れる") {
                        do {
                            try store.sendLetter(on: can, text: text)
                            SoundPlayer.shared.play(.gakon)
                            Haptics.success()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Spacer()
        }
        .padding(24)
        .alert("入れられませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
