import SwiftUI

/// 最初の画面：名前とアイコンを決める
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var emoji = "🙂"
    /// 背景の時刻（文字を打つたびに背景を描き直さないように、画面を開いたときの時刻で固定する）
    @State private var sceneDate = Date()

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            SkyBackgroundView(date: store.adjusted(sceneDate), calendar: store.clock.calendar)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack(alignment: .bottom, spacing: 12) {
                        CanView(title: "今日", mood: .hot, kind: .photo, pattern: .wave, emoji: "🐱", width: 54)
                            .rotationEffect(.degrees(-8))
                        CanView(title: "CanSNS", mood: .cold, kind: .text, pattern: .stripe, emoji: emoji, width: 70)
                        CanView(title: "しゅわ", mood: .fizzy, kind: .voice, pattern: .dots, emoji: "🐶", width: 54)
                            .rotationEffect(.degrees(8))
                    }
                    .padding(.top, 40)

                    VStack(spacing: 8) {
                        Text("CanSNS")
                            .font(.pixel(44))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("友達の今日を、1本ずつ受け取る。")
                            .font(.pixel(16))
                    }
                    .foregroundStyle(.white)
                    // 明るい空の上でも読めるように、上下左右をふち取る
                    .pixelOutline(width: 2)

                    VStack(alignment: .leading, spacing: 14) {
                        PixelHeading(text: "なまえ")
                        PixelTextField(placeholder: "例：たかおか", text: $name)
                        PixelHeading(text: "アイコン")
                        EmojiGrid(selection: $emoji)
                        Button("はじめる") {
                            store.createAccount(name: name, emoji: emoji)
                            NotificationScheduler.requestAndSchedule()
                        }
                        .buttonStyle(PixelButtonStyle(color: Theme.machineBody, fontSize: 18))
                        .disabled(trimmedName.isEmpty)
                    }
                    .pixelWindow(padding: 16)
                }
                .padding()
            }
        }
    }
}

/// 自販機を作る・招待コードで参加する・デモで試す
struct MachineSetupView: View {
    var isSheet = false

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var machineName = ""
    @State private var inviteCode = ""
    @State private var errorMessage: String?
    @State private var isJoining = false
    @State private var sceneDate = Date()

    var body: some View {
        ZStack {
            SkyBackgroundView(date: store.adjusted(sceneDate), calendar: store.clock.calendar)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("自販機をえらぼう")
                            .font(.pixel(28))
                        Text("自販機 ＝ 友達グループです。少人数（\(MachineRules.minimumMembersToOpen)〜\(MachineRules.maxMembers)人）で使います。")
                            .font(.pixel(14))
                    }
                    .pixelWindow()
                    .padding(.top, isSheet ? 8 : 24)

                    // 新しく置く
                    VStack(alignment: .leading, spacing: 12) {
                        PixelHeading(text: "新しく自販機を置く")
                        PixelTextField(placeholder: "名前（例：放課後の自販機）", text: $machineName)
                        Button("ここに置く") {
                            store.createMachine(name: machineName)
                            finish()
                        }
                        .buttonStyle(PixelButtonStyle(color: Theme.machineBody))
                    }
                    .pixelWindow()

                    // 招待コードで参加
                    VStack(alignment: .leading, spacing: 12) {
                        PixelHeading(text: "招待コードで参加する")
                        PixelTextField(placeholder: "6文字のコード", text: $inviteCode, monospaced: true)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button {
                            join()
                        } label: {
                            Text(isJoining ? "参加しています…" : "参加する")
                        }
                        .buttonStyle(PixelButtonStyle(color: Pixel.yellow, textColor: Pixel.ink))
                        .disabled(inviteCode.trimmingCharacters(in: .whitespaces).count < 6 || isJoining)
                        if store.mode == .local {
                            Text("※ オフラインモードでは、同じ端末で作った自販機にだけ参加できます")
                                .font(.pixel(11))
                                .opacity(0.75)
                        }
                    }
                    .pixelWindow()

                    if store.mode == .local {
                        VStack(alignment: .leading, spacing: 12) {
                            PixelHeading(text: "デモで試す")
                            Text("友達ボット3人がいる自販機で、納品→開店→開封→冷蔵庫の流れを1人で体験できます。")
                                .font(.pixel(13))
                                .opacity(0.85)
                            Button("デモの自販機を置く") {
                                store.startDemo()
                                finish()
                            }
                            .buttonStyle(PixelButtonStyle(color: Pixel.green, textColor: Pixel.ink))
                        }
                        .pixelWindow()
                    }
                }
                .padding()
            }
        }
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                        .tint(.white)
                }
            }
        }
        // シートのときは、上の帯を暗いウィンドウの色にして「とじる」を読みやすくする
        .toolbarBackground(Pixel.windowFill, for: .navigationBar)
        .toolbarBackground(isSheet ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(isSheet ? .dark : nil, for: .navigationBar)
        .alert("参加できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func join() {
        isJoining = true
        Task {
            do {
                try await store.joinMachine(inviteCode: inviteCode)
                finish()
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }

    private func finish() {
        SoundPlayer.shared.play(.gakon)
        if isSheet { dismiss() }
    }
}
