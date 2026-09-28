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

/// 自販機（アプリアイコンと同じ、赤いドット絵の自販機）
struct VendingMachineView: View {
    var machineName: String
    var slots: [MachineSlot]
    var lamps: [String: SlotLamp]
    var isOpenPhase: Bool
    var level: Int
    var effects: [MachineEffect]
    var digits: String
    var onTap: (MachineSlot) -> Void

    @State private var neonPhase = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
    private let canWidth: CGFloat = 36
    private let sidePanelWidth: CGFloat = 56

    private var hasNeon: Bool { effects.contains(.limitedNeon) }
    private var isFull: Bool { effects.contains(.fullStock) }

    var body: some View {
        VStack(spacing: 0) {
            machineBody
            feet
        }
        .frame(maxWidth: 340)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                neonPhase = true
            }
        }
    }

    // MARK: - 本体

    private var machineBody: some View {
        VStack(spacing: 8) {
            sign
            HStack(alignment: .top, spacing: 8) {
                display
                sidePanel
            }
            outletRow
        }
        .padding(12)
        .background(bodyShape)
        .background(nightGlow)
    }

    private var bodyShape: some View {
        ZStack {
            PixelFrame(fill: Theme.machineBody, border: Pixel.ink, borderWidth: 4, step: 6,
                       shadow: .black.opacity(0.35), shadowOffset: 6)
            // 右側の影（立体感）
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Theme.machineBodyDark.frame(width: 10)
            }
            .padding(.vertical, 8)
            .padding(.trailing, 4)
            // 左上のハイライト
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Theme.machineHighlight.frame(width: 16, height: 4)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 0) {
                    Theme.machineHighlight.frame(width: 4, height: 12)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 7)
            .padding(.leading, 7)
            // 限定ネオン：縁がピンクと水色に点滅する
            if hasNeon {
                PixelBox(step: 6)
                    .stroke(neonPhase ? Color.pink : Color.cyan, lineWidth: 4)
                    .padding(-4)
            }
        }
    }

    /// 開店中は、自販機のまわりがぼんやり明るい
    @ViewBuilder
    private var nightGlow: some View {
        if isOpenPhase {
            PixelBox(step: 12)
                .fill(Color(hex: 0xFFF1B8).opacity(0.22))
                .padding(-14)
        }
    }

    // MARK: - 上の看板

    private var sign: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                // レベルが上がるとライトが増える
                ForEach(0..<min(max(level, 1), 8), id: \.self) { _ in
                    Rectangle()
                        .fill(isOpenPhase ? Pixel.yellow : Pixel.yellow.opacity(0.35))
                        .frame(width: 5, height: 5)
                }
            }
            Text(machineName)
                .font(.pixel(18, fixed: true))
                .foregroundStyle(hasNeon ? Color.pink : Theme.machineBodyDark)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(isFull ? "満タン！全員そろいました" : "Lv.\(level) \(MachineGrowth.title(for: level))")
                .font(.pixel(10, fixed: true))
                .foregroundStyle(Pixel.ink.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            PixelFrame(fill: isOpenPhase ? Pixel.cream : Color(hex: 0xD9CFB0), border: Pixel.ink,
                       borderWidth: 3, step: 3)
        )
    }

    // MARK: - 缶が並ぶショーケース

    private var display: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(slots) { slot in
                Button {
                    onTap(slot)
                } label: {
                    slotView(slot)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            PixelFrame(fill: isOpenPhase ? Color(hex: 0xF4FBFF) : Color(hex: 0xC9D3DF), border: Pixel.ink,
                       borderWidth: 4, step: 3)
        )
    }

    @ViewBuilder
    private func slotView(_ slot: MachineSlot) -> some View {
        let lamp = lamps[slot.id] ?? .recruiting
        VStack(spacing: 3) {
            Group {
                switch slot.content {
                case .recruiting:
                    EmptyCanView(width: canWidth, glyph: "+")
                case .soldOut:
                    EmptyCanView(width: canWidth)
                case .stocked(let can, let author):
                    CanView(can: can, emoji: author.emoji, width: canWidth)
                        .overlay(alignment: .topTrailing) {
                            if slot.isNew {
                                NewBadge()
                                    .offset(x: 10, y: -6)
                            }
                        }
                }
            }
            .frame(height: canWidth * 1.75)

            // 棚板
            Pixel.ink.opacity(0.85)
                .frame(height: 3)

            Group {
                // 値段の位置に、気分の帯
                switch slot.content {
                case .stocked(let can, _):
                    MoodStrip(mood: can.mood, fontSize: 8)
                default:
                    Text("ーーー")
                        .font(.pixel(8, fixed: true))
                        .foregroundStyle(Pixel.ink.opacity(0.4))
                }
            }
            .frame(height: 12)

            Text(ownerName(slot))
                .font(.pixel(9, fixed: true))
                .foregroundStyle(Pixel.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)

            // 押しボタンのランプ
            Text(lamp.text)
                .font(.pixel(8, fixed: true))
                .foregroundStyle(lamp.isLit ? Pixel.ink : Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(lamp.color)
                .overlay(Rectangle().strokeBorder(Pixel.ink, lineWidth: 1.5))
                .padding(.horizontal, 3)
        }
    }

    private func ownerName(_ slot: MachineSlot) -> String {
        switch slot.content {
        case .recruiting: "あき"
        case .soldOut(let user): user.name
        case .stocked(_, let user): user.name
        }
    }

    // MARK: - 右側のパネル（ルーレット・コイン投入口・テンキー・札入れ）

    private var sidePanel: some View {
        VStack(spacing: 8) {
            // 4桁ルーレット
            HStack(spacing: 1) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.pixel(12, fixed: true))
                        .foregroundStyle(Theme.digit)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(PixelFrame(fill: .black, border: Pixel.ink, borderWidth: 2, step: 2))

            // コイン投入口
            ZStack {
                PixelFrame(fill: Theme.panel, border: Pixel.ink, borderWidth: 2, step: 2)
                Rectangle()
                    .fill(Color(hex: 0xB5BAC4))
                    .frame(width: 4, height: 14)
            }
            .frame(width: 30, height: 26)

            // テンキー
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { _ in
                            Rectangle()
                                .fill(Color(hex: 0xD9DDE3))
                                .frame(width: 9, height: 7)
                        }
                    }
                }
            }
            .padding(5)
            .background(PixelFrame(fill: Theme.panel, border: Pixel.ink, borderWidth: 2, step: 2))

            // 札入れ
            ZStack {
                PixelFrame(fill: Pixel.yellow, border: Pixel.ink, borderWidth: 2, step: 2)
                Rectangle()
                    .fill(Pixel.ink)
                    .frame(width: 18, height: 3)
            }
            .frame(width: 34, height: 18)

            Text("FREE")
                .font(.pixel(9, fixed: true))
                .foregroundStyle(.white)
        }
        .frame(width: sidePanelWidth)
    }

    // MARK: - 取り出し口

    private var outletRow: some View {
        HStack(spacing: 8) {
            ZStack {
                PixelFrame(fill: Pixel.ink, border: Pixel.ink, borderWidth: 3, step: 3)
                // 取り出し口のフタ
                Rectangle()
                    .fill(Color(hex: 0x5A5F6B))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .offset(y: -9)
                Text("とりだしぐち")
                    .font(.pixel(10, fixed: true))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 44)

            // 返却レバー
            PixelFrame(fill: Theme.machineBodyDark, border: Pixel.ink, borderWidth: 2, step: 2)
                .frame(width: 22, height: 22)
                .frame(width: sidePanelWidth)
        }
    }

    // MARK: - 脚

    private var feet: some View {
        HStack {
            Pixel.ink.frame(width: 30, height: 8)
            Spacer()
            Pixel.ink.frame(width: 30, height: 8)
        }
        .padding(.horizontal, 22)
    }
}

/// 新しく納品された缶につく「NEW」バッジ（チカチカ点滅する）
struct NewBadge: View {
    @State private var blink = false

    var body: some View {
        Text("NEW")
            .font(.pixel(8, fixed: true))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Color(hex: 0xE0282E))
            .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1.5))
            .opacity(blink ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
    }
}
