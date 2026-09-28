import SwiftUI

/// 缶の絵。ラベルの色は「今日の気分」、柄はテンプレート、アイコンは中身の種類で決まる。
struct CanView: View {
    var title: String
    var mood: Mood
    var kind: ContentKind
    var pattern: LabelPattern
    var emoji: String
    var width: CGFloat
    var tabOpen: Bool = false
    /// 中身の種類のアイコンを出すか（開ける前は中身がわからないように出さない）
    var showsKind: Bool = false

    init(title: String, mood: Mood, kind: ContentKind, pattern: LabelPattern,
         emoji: String, width: CGFloat, tabOpen: Bool = false, showsKind: Bool = false) {
        self.title = title
        self.mood = mood
        self.kind = kind
        self.pattern = pattern
        self.emoji = emoji
        self.width = width
        self.tabOpen = tabOpen
        self.showsKind = showsKind
    }

    init(can: CanPost, emoji: String, width: CGFloat, tabOpen: Bool = false, showsKind: Bool = false) {
        self.init(title: can.title, mood: can.mood, kind: can.kind, pattern: can.pattern,
                  emoji: emoji, width: width, tabOpen: tabOpen, showsKind: showsKind)
    }

    private var height: CGFloat { width * 1.75 }
    private var corner: CGFloat { width * 0.16 }

    var body: some View {
        ZStack(alignment: .top) {
            // 銀色の胴体
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.55), Color(white: 0.93), Color(white: 0.72), Color(white: 0.5)],
                    startPoint: .leading, endPoint: .trailing
                ))

            label
                .frame(width: width, height: height * 0.7)
                .offset(y: height * 0.16)

            // 丸みを出すための光と影
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .white.opacity(0.38), location: 0.3),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.32), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                ))
                .allowsHitTesting(false)

            lid
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: width * 0.04, y: width * 0.03)
        .accessibilityElement()
        .accessibilityLabel(showsKind ? "\(title)、\(mood.stripText)、\(kind.label)" : "\(title)、\(mood.stripText)")
    }

    private var label: some View {
        ZStack {
            LinearGradient(colors: [mood.color, mood.deepColor], startPoint: .top, endPoint: .bottom)
            PatternOverlay(pattern: pattern)
            VStack(spacing: width * 0.05) {
                if showsKind {
                    Image(systemName: kind.symbol)
                        .font(.system(size: width * 0.15, weight: .bold))
                }
                Text(title)
                    .font(.system(size: width * 0.17, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, width * 0.07)
                Text(emoji)
                    .font(.system(size: width * 0.17))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        }
    }

    /// 上ぶたとプルタブ
    private var lid: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.45)],
                                     startPoint: .top, endPoint: .bottom))
            if tabOpen {
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: width * 0.22, height: height * 0.028)
            }
            Capsule()
                .fill(Color(white: 0.88))
                .overlay(Capsule().stroke(Color(white: 0.5), lineWidth: 0.5))
                .frame(width: width * 0.34, height: height * 0.032)
                .rotation3DEffect(.degrees(tabOpen ? 70 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
                .offset(y: tabOpen ? -height * 0.012 : 0)
        }
        .frame(width: width, height: height * 0.075)
    }
}

/// まだ納品されていない枠に置く、灰色の缶のシルエット
struct EmptyCanView: View {
    var width: CGFloat
    var symbol: String = "questionmark"

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: width * 0.3, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            )
            .frame(width: width, height: width * 1.75)
    }
}

/// ラベルの柄（ストライプ・ドット・ウェーブ）
struct PatternOverlay: View {
    var pattern: LabelPattern

    var body: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(.white.opacity(0.2))
            switch pattern {
            case .plain:
                break
            case .stripe:
                var x = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: color, lineWidth: size.width * 0.08)
                    x += size.width * 0.28
                }
            case .dots:
                let step = size.width * 0.22
                let radius = step * 0.22
                var y = step / 2
                var row = 0
                while y < size.height {
                    var x = row.isMultiple(of: 2) ? step / 2 : step
                    while x < size.width {
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: color)
                        x += step
                    }
                    y += step
                    row += 1
                }
            case .wave:
                let lines = 5
                let amplitude = size.height * 0.03
                for line in 0..<lines {
                    let baseY = size.height * (CGFloat(line) + 0.5) / CGFloat(lines)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: baseY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let angle = Double(x / size.width) * 2 * Double.pi * 1.5
                        path.addLine(to: CGPoint(x: x, y: baseY + amplitude * CGFloat(sin(angle))))
                        x += 2
                    }
                    context.stroke(path, with: color, lineWidth: size.width * 0.04)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    HStack(spacing: 16) {
        CanView(title: "部活おわり", mood: .hot, kind: .photo, pattern: .wave, emoji: "🐱", width: 80, showsKind: true)
        CanView(title: "小テスト", mood: .fizzy, kind: .text, pattern: .dots, emoji: "🐶", width: 80, tabOpen: true)
        CanView(title: "帰り道", mood: .cold, kind: .voice, pattern: .stripe, emoji: "🐰", width: 80)
        EmptyCanView(width: 80)
    }
    .padding()
    .background(Color.gray)
}
