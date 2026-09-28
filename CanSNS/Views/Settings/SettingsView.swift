import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showProfileEdit = false
    @State private var showMachineSetup = false
    @State private var showInvite = false
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        // Toggle に渡す「バインディング」を作るためのラッパー
        @Bindable var bindable = store
        NavigationStack {
            Form {
                profileSection
                machineSection
                Section("サウンド") {
                    Toggle("効果音（ガコン！プシュッ！）", isOn: $bindable.soundEnabled)
                }
                developerSection
                rulesSection
            }
            .navigationTitle("設定")
            .toast($message)
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditView()
            }
            .sheet(isPresented: $showMachineSetup) {
                NavigationStack {
                    MachineSetupView(isSheet: true)
                }
            }
            .sheet(isPresented: $showInvite) {
                InviteSheet()
                    .presentationDetents([.medium])
            }
            .confirmationDialog("すべてのデータを消しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("消す", role: .destructive) { store.resetAll() }
            } message: {
                Text("ユーザー・自販機・缶・写真などがすべて消えます")
            }
        }
    }

    // MARK: - プロフィール

    private var profileSection: some View {
        Section("プロフィール") {
            if let user = store.currentUser {
                HStack {
                    Text(user.emoji)
                        .font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text(user.name)
                            .font(.headline)
                        if user.isDemo {
                            Text("デモの友達になりきり中")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Button("編集") { showProfileEdit = true }
                }
            }
        }
    }

    // MARK: - 自販機

    @ViewBuilder
    private var machineSection: some View {
        if let machine = store.currentMachine {
            let total = store.db.totalCans(in: machine.id)
            let level = MachineGrowth.level(totalCans: total)
            let streak = store.db.deliveryStreak(machineID: machine.id, endingAt: store.today, clock: store.clock)
            Section("自販機") {
                LabeledContent("名前", value: machine.name)
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("レベル", value: "Lv.\(level) \(MachineGrowth.title(for: level))")
                    if let progress = MachineGrowth.progress(totalCans: total) {
                        ProgressView(value: progress.fraction)
                        Text("あと\(progress.remaining)本の納品でレベルアップ（累計\(total)本）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("連続納品", value: "\(streak)日（\(MachineEffect.neonStreakDays)日で限定ネオン）")
                Button {
                    showInvite = true
                } label: {
                    LabeledContent("招待コード", value: machine.inviteCode)
                }
                DisclosureGroup("メンバー（\(machine.members.count)/\(MachineRules.maxMembers)人）") {
                    ForEach(machine.memberIDs, id: \.self) { userID in
                        if let user = store.user(userID) {
                            Text("\(user.emoji) \(user.name)\(user.isDemo ? "（デモ）" : "")")
                        }
                    }
                }
                if store.myMachines.count > 1 {
                    Picker("表示する自販機", selection: Binding(
                        get: { machine.id },
                        set: { store.selectMachine($0) }
                    )) {
                        ForEach(store.myMachines) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                }
                Button("ほかの自販機を作る・参加する") { showMachineSetup = true }
            }
        }
    }

    // MARK: - 開発者メニュー

    private var developerSection: some View {
        Section {
            LabeledContent("モード", value: store.mode == .cloud ? "Firebase（友達と共有）" : "オフライン（この端末だけ）")
            if store.mode == .cloud {
                Button("オフライン（デモ）モードに切り替える") { store.setLocalMode(true) }
            } else {
                if store.isCloudAvailable {
                    Button("Firebase モードに戻す") { store.setLocalMode(false) }
                }
                offlineTools
            }
        } header: {
            Text("開発者メニュー（テスト用）")
        } footer: {
            Text(store.mode == .cloud
                 ? "Firebase モードでは、開店・廃棄の時刻はサーバーの時計で判定されます。1人で流れを試したいときはオフラインモードへ。"
                 : "時刻を動かすと、納品中→開店→廃棄の流れを1人で試せます。「なりきる」で友達側の操作も確認できます。")
        }
    }

    @ViewBuilder
    private var offlineTools: some View {
        LabeledContent("アプリ内の時刻", value: DateText.monthDayTime(store.now))
        HStack {
            timeButton("朝 8:00", hour: 8)
            timeButton("夜 21:30", hour: 21, minute: 30)
            timeButton("深夜 2:00", hour: 2)
        }
        .buttonStyle(.bordered)
        Button("翌朝 6:05 に進める（廃棄を確認）") {
            store.skipToNextMorning()
            message = "翌朝になりました。昨日の缶は冷蔵庫へ"
        }
        if store.isTimeShifted {
            Button("本当の時刻に戻す") { store.resetTime() }
        }

        if let machine = store.currentMachine {
            Picker("なりきるユーザー", selection: Binding(
                get: { store.currentUserID ?? "" },
                set: { store.switchUser(to: $0) }
            )) {
                ForEach(machine.memberIDs, id: \.self) { userID in
                    if let user = store.user(userID) {
                        Text("\(user.emoji) \(user.name)").tag(userID)
                    }
                }
            }
        }
        Button("デモの友達に納品してもらう") {
            store.letFriendsDeliver()
            message = "友達の缶が入荷しました"
        }
        Button("デモの友達に自分の缶を開けてもらう") {
            message = store.letFriendsReactToMyCan()
                ? "友達が開けてくれました。お知らせを見てみよう"
                : "先に今日の缶を納品してください"
        }
        Button("すべてのデータを消す", role: .destructive) { confirmReset = true }
    }

    private func timeButton(_ title: String, hour: Int, minute: Int = 0) -> some View {
        Button(title) {
            store.setTime(hour: hour, minute: minute)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    // MARK: - ルール説明

    private var rulesSection: some View {
        Section("CanSNS のルール") {
            ruleRow("6:00〜20:59", "納品の時間。友達の缶のラベルは見えるけど、まだ開けられない")
            ruleRow("21:00", "開店！缶を開けて、友達の今日を受け取ろう（開店中も納品OK）")
            ruleRow("翌6:00", "廃棄。自分の缶は自分の冷蔵庫へ")
            ruleRow("何本でも", "1日に何本でも納品できる（動画・音声は15秒まで）")
            ruleRow("\(MachineRules.minimumMembersToOpen)人から", "自販機は\(MachineRules.minimumMembersToOpen)人以上集まると開店できる")
        }
    }

    private func ruleRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProfileEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🙂"

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("名前", text: $name)
                }
                Section("アイコン") {
                    EmojiGrid(selection: $emoji)
                }
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateProfile(name: name, emoji: emoji)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = store.currentUser?.name ?? ""
                emoji = store.currentUser?.emoji ?? "🙂"
            }
        }
    }
}

/// アイコンに使う絵文字を選ぶ
struct EmojiGrid: View {
    @Binding var selection: String
    static let choices = ["🙂", "😎", "🐱", "🐶", "🐰", "🐻", "🐼", "🦊", "🐸", "🐧", "🦄", "🐙",
                          "🍙", "🍓", "⚽️", "🎧", "🎸", "📚", "🌙", "🌈"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
            ForEach(Self.choices, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                        .font(.title)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle().fill(selection == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            Circle().strokeBorder(selection == emoji ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
