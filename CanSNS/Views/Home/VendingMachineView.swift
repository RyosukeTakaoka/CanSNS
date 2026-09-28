import SwiftUI

/// 自販機の1枠ぶんの情報
struct MachineSlot: Identifiable {
    enum Content {
        /// まだメンバーがいない枠
        case recruiting
        /// メンバーはいるが、今日はまだ納品していない（売り切れ）
        case soldOut(UserProfile)
        /// 缶が入っている
        case stocked(CanPost, UserProfile)
    }

    var id: String
    var content: Content
    /// まだ見ていない新しい缶か（NEW バッジを出す）
    var isNew: Bool = false
}

/// ボタンのランプの状態
enum SlotLamp {
    case selling, preparing, soldOut, purchased, mine, recruiting

    var text: String {
        switch self {
        case .selling: "販売中"
        case .preparing: "準備中"
        case .soldOut: "売切"
        case .purchased: "購入済"
        case .mine: "じぶん"
        case .recruiting: "募集中"
        }
    }

    var color: Color {
        switch self {
        case .selling: Theme.lampOn
        case .soldOut: Theme.lampSoldOut
        case .purchased: Color(hex: 0xFFC94D)
        case .mine: Color(hex: 0x8EC5FF)
        case .preparing, .recruiting: Theme.lampIdle
        }
    }

    var isLit: Bool {
        switch self {
        case .preparing, .recruiting: false
        default: true
        }
    }
}

struct VendingMachineView: View {
    var machineName: String
    var slots: [MachineSlot]
    var lamps: [String: SlotLamp]
    var isOpenPhase: Bool
    var level: Int
    var effects: [MachineEffect]
    var digits: String
    var onTap: (MachineSlot) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    private let canWidth: CGFloat = 42

    private var hasNeon: Bool { effects.contains(.limitedNeon) }
    private var isFull: Bool { effects.contains(.fullStock) }

    var body: some View {
        VStack(spacing: 0) {
            sign
            VStack(spacing: 10) {
                display
                controlPanel
                outlet
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.machineBody, Theme.machineBodyDark],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hasNeon ? neonGradient : AngularGradient(colors: [Theme.machineTrim, Theme.machineTrim], center: .center),
                              lineWidth: hasNeon ? 4 : 3)
                .shadow(color: hasNeon ? Color.pink.opacity(0.9) : .clear, radius: 10)
        )
        .shadow(color: isOpenPhase ? Color(hex: 0xBFE3FF).opacity(0.55) : .black.opacity(0.35),
                radius: isOpenPhase ? 28 : 12, y: 6)
        .frame(maxWidth: 340)
    }

    private var neonGradient: AngularGradient {
        AngularGradient(colors: [.pink, .purple, .cyan, .green, .yellow, .orange, .pink], center: .center)
    }

    // MARK: - 上の看板

    private var sign: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                // レベルが上がるとライトが増える
                ForEach(0..<min(max(level, 1), 8), id: \.self) { _ in
                    Circle()
                        .fill(isOpenPhase ? Color.yellow : Color.yellow.opacity(0.35))
                        .frame(width: 6, height: 6)
                        .shadow(color: isOpenPhase ? .yellow : .clear, radius: 3)
                }
            }
            Text(machineName)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(hasNeon ? Color.pink : Theme.machineBodyDark)
                .shadow(color: hasNeon ? .pink : .clear, radius: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(isFull ? "満タン！全員そろいました" : "Lv.\(level) \(MachineGrowth.title(for: level))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.machineBodyDark.opacity(0.8))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                .fill(Theme.machineTrim)
        )
    }

    // MARK: - 缶が並ぶショーケース

    private var display: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(slots) { slot in
                Button {
                    onTap(slot)
                } label: {
                    slotView(slot)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: isOpenPhase
                        ? [Color(hex: 0xF4FAFF), Color(hex: 0xC9E4FF)]
                        : [Color(hex: 0xC5D3E6), Color(hex: 0x9FB3CF)],
                    startPoint: .top, endPoint: .bottom
                ))
        )
        .overlay(
            // ガラスの反射
            LinearGradient(colors: [.white.opacity(0.35), .clear, .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func slotView(_ slot: MachineSlot) -> some View {
        let lamp = lamps[slot.id] ?? .recruiting
        VStack(spacing: 4) {
            Group {
                switch slot.content {
                case .recruiting:
                    EmptyCanView(width: canWidth, symbol: "person.badge.plus")
                case .soldOut:
                    EmptyCanView(width: canWidth)
                case .stocked(let can, let author):
                    CanView(can: can, emoji: author.emoji, width: canWidth)
                        .overlay(alignment: .topTrailing) {
                            if slot.isNew {
                                NewBadge()
                                    .offset(x: 12, y: -6)
                            }
                        }
                }
            }
            .frame(height: canWidth * 1.75)

            // 値段の位置に、気分の帯と名前
            Group {
                switch slot.content {
                case .stocked(let can, _):
                    MoodStrip(mood: can.mood, fontSize: 8)
                default:
                    Text("ーーー")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 1.6)
                }
            }
            .frame(height: 13)

            Text(ownerName(slot))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x33415C))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // 押しボタンのランプ
            Text(lamp.text)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(lamp.isLit ? Color.black.opacity(0.75) : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Capsule().fill(lamp.color))
                .shadow(color: lamp.isLit ? lamp.color : .clear, radius: 4)
        }
    }

    private func ownerName(_ slot: MachineSlot) -> String {
        switch slot.content {
        case .recruiting: "あき"
        case .soldOut(let user): user.name
        case .stocked(_, let user): user.name
        }
    }

    // MARK: - ルーレットとコイン投入口（飾り）

    private var controlPanel: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.digit)
                        .shadow(color: Theme.digit.opacity(0.8), radius: 4)
                        .frame(width: 18)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 6))

            Spacer()

            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 4, height: 22)
                    .padding(6)
                    .background(Color(white: 0.8), in: RoundedRectangle(cornerRadius: 6))
                Text("FREE")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(8)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 取り出し口

    private var outlet: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(5)
            Text("とりだしぐち")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(height: 46)
    }
}

/// 新しく納品された缶につく「NEW」バッジ
struct NewBadge: View {
    @State private var pulse = false

    var body: some View {
        Text("NEW")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1))
            .scaleEffect(pulse ? 1.12 : 0.95)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
