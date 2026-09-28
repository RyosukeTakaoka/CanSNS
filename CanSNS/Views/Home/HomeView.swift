import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showDeliver = false
    @State private var openingCan: CanPost?
    @State private var viewingCan: CanPost?
    @State private var showInvite = false
    @State private var toast: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: store.adjusted(context.date))
        }
        .toast($toast)
        .sheet(isPresented: $showDeliver) {
            DeliverView()
        }
        .sheet(item: $viewingCan) { can in
            NavigationStack {
                CanContentView(can: can)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("とじる") { viewingCan = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteSheet()
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: $openingCan) { can in
            OpenFlowView(can: can)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let machine = store.currentMachine, let me = store.currentUser {
            let clock = store.clock
            let today = clock.businessDay(for: now)
            let phase = clock.phase(at: now)
            let effects = store.db.effects(machineID: machine.id, day: today, clock: clock)
            let todaysCans = store.db.cans(in: machine.id, on: today)
            let myCans = todaysCans.filter { $0.authorID == me.id }

            ZStack {
                SkyBackgroundView(date: now, calendar: clock.calendar)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        statusHeader(now: now, today: today, phase: phase)
                        if machine.members.count < MachineRules.minimumMembersToOpen {
                            recruitingBanner(machine: machine)
                        }
                        ForEach(effects) { effect in
                            EffectBanner(effect: effect)
                        }
                        VendingMachineView(
                            machineName: machine.name,
                            slots: slots(for: machine, cans: todaysCans),
                            lamps: lamps(for: machine, cans: todaysCans, phase: phase, me: me.id),
                            isOpenPhase: phase == .open,
                            level: MachineGrowth.level(totalCans: store.db.totalCans(in: machine.id)),
                            effects: effects,
                            digits: digits(for: today),
                            onTap: { slot in handleTap(slot, me: me.id) }
                        )
                        deliverSection(myCans: myCans, me: me)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - 上部の営業状況

    private func statusHeader(now: Date, today: BusinessDay, phase: BusinessPhase) -> some View {
        let next = store.clock.nextTransition(after: now)
        let remaining = BusinessClock.countdownText(next.timeIntervalSince(now))
        return HStack(spacing: 10) {
            Image(systemName: phase == .open ? "moon.stars.fill" : "sun.max.fill")
                .font(.title2)
                .foregroundStyle(phase == .open ? Color.yellow : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(today.shortText)の自販機・\(phase.title)")
                    .font(.headline)
                Text(phase == .open ? "廃棄（翌6:00）まで \(remaining)" : "開店（21:00）まで \(remaining)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isTimeShifted {
                Label("時刻テスト中", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recruitingBanner(machine: Machine) -> some View {
        let needed = MachineRules.minimumMembersToOpen - machine.members.count
        return Button {
            showInvite = true
        } label: {
            HStack {
                Image(systemName: "person.2.badge.plus")
                VStack(alignment: .leading, spacing: 2) {
                    Text("あと\(needed)人で開店できます")
                        .font(.subheadline.bold())
                    Text("招待コード \(machine.inviteCode) を友達に送ろう")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 納品ボタン

    /// 納品ボタン（何本でも納品できる）と、今日自分が納品した缶
    private func deliverSection(myCans: [CanPost], me: UserProfile) -> some View {
        VStack(spacing: 10) {
            Button {
                SoundPlayer.shared.play(.beep)
                showDeliver = true
            } label: {
                Label(myCans.isEmpty ? "今日の缶を納品する" : "もう1本納品する", systemImage: "shippingbox.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Theme.machineBody.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            }
            .buttonStyle(.plain)

            if !myCans.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("今日納品した缶 \(myCans.count)本")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(store.clock.phase(at: store.now) == .delivery ? "21:00の開店を待っています" : "営業中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(myCans.reversed())) { can in
                                Button {
                                    viewingCan = can
                                } label: {
                                    VStack(spacing: 4) {
                                        CanView(can: can, emoji: me.emoji, width: 40)
                                        Text("開けた人 \(store.db.openings(of: can.id).count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - 自販機の中身を組み立てる

    /// 今日の缶をすべて並べ、まだ1本も納品していないメンバーは「売切」、残りは「募集中」の空き枠
    private func slots(for machine: Machine, cans: [CanPost]) -> [MachineSlot] {
        var result: [MachineSlot] = cans.compactMap { can in
            guard let author = store.user(can.authorID) else { return nil }
            return MachineSlot(id: can.id, content: .stocked(can, author), isNew: store.isNew(can))
        }
        let authors = Set(cans.map(\.authorID))
        for userID in machine.memberIDs where !authors.contains(userID) {
            if let user = store.user(userID) {
                result.append(MachineSlot(id: userID, content: .soldOut(user)))
            }
        }
        // 4の倍数になるまで空き枠で埋める
        var index = 0
        while result.count < 4 || !result.count.isMultiple(of: 4) {
            result.append(MachineSlot(id: "empty-\(index)", content: .recruiting))
            index += 1
        }
        return result
    }

    private func lamps(for machine: Machine, cans: [CanPost], phase: BusinessPhase,
                       me: String) -> [String: SlotLamp] {
        var result: [String: SlotLamp] = [:]
        let canOpen = phase == .open && machine.members.count >= MachineRules.minimumMembersToOpen
        for can in cans {
            if can.authorID == me {
                result[can.id] = .mine
            } else if store.db.hasOpened(canID: can.id, userID: me) {
                result[can.id] = .purchased
            } else {
                result[can.id] = canOpen ? .selling : .preparing
            }
        }
        for userID in machine.memberIDs where result[userID] == nil {
            result[userID] = .soldOut
        }
        return result
    }

    /// ルーレット表示（ふだんは日付を表示）
    private func digits(for day: BusinessDay) -> String {
        let month = day.month < 10 ? "0\(day.month)" : "\(day.month)"
        let date = day.day < 10 ? "0\(day.day)" : "\(day.day)"
        return month + date
    }

    // MARK: - 枠をタップしたとき

    private func handleTap(_ slot: MachineSlot, me: String) {
        switch slot.content {
        case .recruiting:
            showInvite = true
        case .soldOut(let user):
            if user.id == me {
                showDeliver = true
            } else {
                toast = "\(user.name)はまだ納品していません（売切）"
            }
        case .stocked(let can, _):
            store.markSeen(can)
            if can.authorID == me || store.hasOpened(can) {
                // 自分の缶・一度開けた缶は、演出なしで中身を見る
                viewingCan = can
            } else if let reason = store.openBlockReason(for: can) {
                SoundPlayer.shared.play(.beep)
                toast = "「\(can.title)」\n\(reason)"
            } else {
                openingCan = can
            }
        }
    }
}

/// 条件達成の演出バナー
struct EffectBanner: View {
    var effect: MachineEffect
    @State private var glow = false

    var body: some View {
        HStack(spacing: 12) {
            Text(effect.emoji)
                .font(.title)
                .scaleEffect(glow ? 1.15 : 0.95)
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.title)
                    .font(.headline)
                Text(effect.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: [.pink, .purple, .cyan, .yellow, .pink], center: .center),
                    lineWidth: 2
                )
                .opacity(glow ? 1 : 0.5)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

/// 招待コードを見せるシート
struct InviteSheet: View {
    @Environment(AppStore.self) private var store
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            if let machine = store.currentMachine {
                Text("友達を自販機に招待")
                    .font(.title3.bold())
                Text(machine.inviteCode)
                    .font(.system(size: 40, weight: .heavy, design: .monospaced))
                    .kerning(6)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                Text("\(machine.members.count)/\(MachineRules.maxMembers)人・\(MachineRules.minimumMembersToOpen)人から開店できます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        UIPasteboard.general.string = machine.inviteCode
                        copied = true
                    } label: {
                        Label(copied ? "コピーしました" : "コピー", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: "CanSNSで一緒に自販機やろう🥫 招待コード: \(machine.inviteCode)") {
                        Label("送る", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}
