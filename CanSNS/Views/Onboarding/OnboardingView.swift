import SwiftUI

/// 最初の画面：名前とアイコンを決める
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var emoji = "🙂"

    var body: some View {
        ZStack {
            SkyBackgroundView(date: store.now, calendar: store.clock.calendar)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 10) {
                        CanView(title: "今日", mood: .hot, kind: .photo, pattern: .wave, emoji: "🐱", width: 54)
                            .rotationEffect(.degrees(-8))
                        CanView(title: "CanSNS", mood: .cold, kind: .text, pattern: .stripe, emoji: emoji, width: 70)
                        CanView(title: "しゅわ", mood: .fizzy, kind: .voice, pattern: .dots, emoji: "🐶", width: 54)
                            .rotationEffect(.degrees(8))
                    }
                    .padding(.top, 40)

                    VStack(spacing: 6) {
                        Text("CanSNS")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                        Text("友達の今日を、1本ずつ受け取る。")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 6)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("名前")
                            .font(.subheadline.bold())
                        TextField("例：たかおか", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("アイコン")
                            .font(.subheadline.bold())
                        EmojiGrid(selection: $emoji)
                        Button {
                            store.createAccount(name: name, emoji: emoji)
                            NotificationScheduler.requestAndSchedule()
                        } label: {
                            Text("はじめる")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(Theme.machineBody, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .card()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("自販機をえらぼう")
                    .font(.title.bold())
                Text("自販機 ＝ 友達グループです。少人数（\(MachineRules.minimumMembersToOpen)〜\(MachineRules.maxMembers)人）で使います。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("新しく自販機を置く", systemImage: "plus.square.fill")
                        .font(.headline)
                    TextField("自販機の名前（例：放課後の自販機）", text: $machineName)
                        .textFieldStyle(.roundedBorder)
                    Button("置く") {
                        store.createMachine(name: machineName)
                        finish()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Label("招待コードで参加する", systemImage: "person.2.fill")
                        .font(.headline)
                    TextField("6文字のコード", text: $inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button {
                        join()
                    } label: {
                        if isJoining {
                            ProgressView()
                        } else {
                            Text("参加する")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inviteCode.count < 6 || isJoining)
                    if store.mode == .local {
                        Text("※ オフラインモードでは、同じ端末で作った自販機にだけ参加できます")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()

                if store.mode == .local {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("デモで試す", systemImage: "sparkles")
                            .font(.headline)
                        Text("友達ボット3人がいる自販機で、納品→開店→開封→冷蔵庫の流れを1人で体験できます。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("デモの自販機を置く") {
                            store.startDemo()
                            finish()
                        }
                        .buttonStyle(.bordered)
                    }
                    .card()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
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
