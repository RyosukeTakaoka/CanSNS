import SwiftUI

/// 缶を開ける演出。
/// 1. ボタンを押す（ピッ）→ 2. 缶が落ちる（ガコン！）→ 3. 取り出し口を上にスワイプ
/// → 4. 缶をタップ（プシュッ！）→ 5. 中身が出てくる
struct OpenFlowView: View {
    let can: CanPost

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case dropping, inOutlet, holding, opening, revealed
    }

    private enum CanPlace {
        case top, outlet, center
    }

    @State private var stage: Stage = .dropping
    @State private var place: CanPlace = .top
    @State private var dragOffset: CGFloat = 0
    @State private var outletShake: CGFloat = 0
    @State private var digits: [Int] = [0, 0, 0, 0]
    @State private var isWin = false
    @State private var tabOpen = false
    @State private var showBubbles = false
    @State private var hintPulse = false
    @State private var errorMessage: String?

    private var author: UserProfile? { store.user(can.authorID) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B1030), Color(hex: 0x252A5E)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if stage == .revealed {
                NavigationStack {
                    CanContentView(can: can, justOpened: true, isWin: isWin)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("とじる") { dismiss() }
                            }
                        }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                GeometryReader { geometry in
                    stageView(size: geometry.size)
                }
            }
        }
        .task {
            await runDrop()
        }
        .alert("開けられませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 演出の画面

    private func stageView(size: CGSize) -> some View {
        let outletY = size.height * 0.74
        let canY: CGFloat
        switch place {
        case .top: canY = -150
        case .outlet: canY = outletY
        case .center: canY = size.height * 0.42
        }
        let canWidth: CGFloat = place == .center ? 130 : 70

        return ZStack {
            // 上：閉じるボタンとルーレット
            VStack(spacing: 16) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    Spacer()
                }
                roulette
                Text(hintText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .opacity(hintPulse ? 1 : 0.55)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: hintPulse)
                Spacer()
            }
            .padding()

            // 取り出し口（奥）
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black)
                .frame(width: size.width * 0.8, height: 110)
                .position(x: size.width / 2, y: outletY)
                .offset(x: outletShake)

            // 缶
            CanView(can: can, emoji: author?.emoji ?? "🙂", width: canWidth, tabOpen: tabOpen)
                .rotationEffect(.degrees(place == .center ? 0 : 90))
                .overlay {
                    if showBubbles {
                        FizzBubbles()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if stage == .holding { openCan() }
                }
                .position(x: size.width / 2, y: canY + dragOffset)

            // 取り出し口のフタ（手前・半透明）
            if stage == .dropping || stage == .inOutlet {
                outletFlap(width: size.width * 0.8)
                    .gesture(swipeGesture)
                    .position(x: size.width / 2, y: outletY)
                    .offset(x: outletShake)
            }
        }
    }

    private var hintText: String {
        switch stage {
        case .dropping: "ガコン…！"
        case .inOutlet: "取り出し口を上にスワイプ ↑"
        case .holding: "缶をタップしてあけよう"
        case .opening: "プシュッ！"
        case .revealed: ""
        }
    }

    private func outletFlap(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 2)
            VStack(spacing: 4) {
                Image(systemName: "chevron.up")
                    .font(.title2.bold())
                    .offset(y: hintPulse && stage == .inOutlet ? -4 : 2)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: hintPulse)
                Text("とりだしぐち")
                    .font(.caption.bold())
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: width, height: 110)
        .rotation3DEffect(.degrees(Double(min(0, dragOffset)) * -0.6), axis: (x: 1, y: 0, z: 0), anchor: .top)
        .contentShape(Rectangle())
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard stage == .inOutlet else { return }
                dragOffset = max(-120, min(0, value.translation.height))
            }
            .onEnded { value in
                guard stage == .inOutlet else { return }
                if value.translation.height < -50 {
                    pullOut()
                } else {
                    withAnimation(.spring()) { dragOffset = 0 }
                }
            }
    }

    /// 4桁ルーレット（全部そろうと「あたり！」。ごほうびはなく、演出だけ）
    private var roulette: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Text("\(digits[index])")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.digit)
                        .shadow(color: Theme.digit, radius: 6)
                        .frame(width: 34)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2)))

            if isWin {
                Text("🎉 あたり！ 4つそろった！")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - 演出の進行

    private func runDrop() async {
        SoundPlayer.shared.play(.beep)
        Haptics.impact(.light)
        Task { await spinRoulette() }

        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeIn(duration: 0.38)) {
            place = .outlet
        }
        try? await Task.sleep(nanoseconds: 380_000_000)

        SoundPlayer.shared.play(.gakon)
        Haptics.impact(.heavy)
        // 取り出し口がガタッと揺れる
        for offset: CGFloat in [8, -6, 4, -2, 0] {
            withAnimation(.easeOut(duration: 0.06)) { outletShake = offset }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        stage = .inOutlet
        hintPulse = true
    }

    private func spinRoulette() async {
        let willWin = Int.random(in: 0..<10) == 0
        for _ in 0..<16 {
            digits = digits.map { _ in Int.random(in: 0...9) }
            SoundPlayer.shared.play(.tick)
            try? await Task.sleep(nanoseconds: 70_000_000)
        }
        if willWin {
            let number = Int.random(in: 0...9)
            digits = [number, number, number, number]
            try? await Task.sleep(nanoseconds: 150_000_000)
            SoundPlayer.shared.play(.win)
            Haptics.success()
            withAnimation(.spring()) { isWin = true }
        } else {
            var result = (0..<4).map { _ in Int.random(in: 0...9) }
            if Set(result).count == 1 { result[3] = (result[3] + 1) % 10 }
            digits = result
        }
    }

    private func pullOut() {
        Haptics.impact(.medium)
        stage = .holding
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            dragOffset = 0
            place = .center
        }
    }

    private func openCan() {
        do {
            try store.open(can)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        store.markSeen(can)
        stage = .opening
        SoundPlayer.shared.play(.pshu)
        Haptics.impact(.rigid)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            tabOpen = true
        }
        showBubbles = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                stage = .revealed
            }
        }
    }
}

/// 開けた瞬間にしゅわしゅわ出る泡
struct FizzBubbles: View {
    @State private var rise = false
    private let bubbles: [(x: CGFloat, size: CGFloat, delay: Double)] = (0..<16).map { index in
        let x = CGFloat((index * 37) % 60) - 30
        let size = CGFloat(4 + (index * 7) % 9)
        return (x, size, Double(index % 8) * 0.05)
    }

    var body: some View {
        ZStack {
            ForEach(0..<bubbles.count, id: \.self) { index in
                let bubble = bubbles[index]
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .background(Circle().fill(Color.white.opacity(0.25)))
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(x: bubble.x, y: rise ? -180 - CGFloat(index % 5) * 20 : -60)
                    .opacity(rise ? 0 : 1)
                    .animation(.easeOut(duration: 1.0).delay(bubble.delay), value: rise)
            }
        }
        .allowsHitTesting(false)
        .onAppear { rise = true }
    }
}
