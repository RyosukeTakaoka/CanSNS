import SwiftUI

/// 自販機の後ろの背景（8bit のドット絵）。
/// アプリアイコンと同じ「田んぼの中の自販機」の風景で、時刻によって空の色・星・窓明かりが変わる。
/// すべて四角形だけで描いている。
struct SkyBackgroundView: View {
    var date: Date
    var calendar: Calendar

    private var hour: Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    var body: some View {
        let hour = self.hour
        let colors = SkyPalette.colors(hour: hour)
        let night = SkyPalette.nightness(hour: hour)
        let seconds = date.timeIntervalSinceReferenceDate

        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let landscape = PixelLandscape(size: size, colors: colors, night: night, hour: hour, seconds: seconds)
            landscape.draw(in: &context)
        }
        .background(Color(rgb: colors.bottom))
        .accessibilityHidden(true)
    }
}

/// 背景の風景を描く係
private struct PixelLandscape {
    let size: CGSize
    let colors: (top: RGB, bottom: RGB)
    let night: Double
    let hour: Double
    let seconds: Double

    /// ドット1つぶんの大きさ（画面の幅から決める）
    var p: CGFloat { max(2, (size.width / 150).rounded()) }
    var horizonY: CGFloat { snap(size.height * 0.58) }
    var fieldBottom: CGFloat { snap(size.height * 0.9) }

    func draw(in context: inout GraphicsContext) {
        drawSky(in: &context)
        drawStars(in: &context)
        drawSunAndMoon(in: &context)
        drawClouds(in: &context)
        drawMountains(in: &context)
        drawTreesAndHouses(in: &context)
        drawPaddies(in: &context)
        drawPath(in: &context)
        drawGrass(in: &context)
        drawPoles(in: &context)
    }

    // MARK: 空

    private func drawSky(in context: inout GraphicsContext) {
        // なめらかなグラデーションではなく、段々の色帯にする（ファミコン風）
        let bands = 12
        let bandHeight = snapUp(horizonY / CGFloat(bands))
        for index in 0..<bands {
            let t = Double(index) / Double(bands - 1)
            let color = Color(rgb: colors.top.mixed(with: colors.bottom, amount: t))
            fill(&context, CGRect(x: 0, y: CGFloat(index) * bandHeight, width: size.width, height: bandHeight + 1), color)
        }
    }

    private func drawStars(in context: inout GraphicsContext) {
        guard night > 0.05 else { return }
        var rng = NoiseGenerator(seed: 42)
        for index in 0..<70 {
            let x = snap(unit(&rng) * size.width)
            let y = snap(unit(&rng) * horizonY * 0.8)
            let twinkle = 0.55 + 0.45 * sin(seconds * 1.3 + Double(index))
            let side = p * (index.isMultiple(of: 9) ? 2 : 1)
            fill(&context, CGRect(x: x, y: y, width: side, height: side), .white.opacity(night * twinkle))
            // 大きい星は十字に光らせる
            if index.isMultiple(of: 9) && twinkle > 0.8 {
                fill(&context, CGRect(x: x - p, y: y + p / 2, width: side + p * 2, height: p / 2),
                     .white.opacity(night * 0.6))
            }
        }
    }

    private func drawSunAndMoon(in context: inout GraphicsContext) {
        if night < 0.9, hour >= 5.5, hour <= 19 {
            // 太陽：朝に左から昇り、夕方に右へ沈む
            let t = (hour - 5.5) / 13.5
            let x = snap(size.width * (0.1 + 0.8 * t))
            let y = snap(horizonY - CGFloat(sin(t * Double.pi)) * horizonY * 0.75)
            pixelCircle(&context, center: CGPoint(x: x, y: y), radius: p * 6,
                        color: Color(hex: 0xFFD66B).opacity(1 - night))
        }
        if night > 0.1 {
            // 三日月
            let center = CGPoint(x: snap(size.width * 0.8), y: snap(horizonY * 0.18))
            pixelCircle(&context, center: center, radius: p * 5, color: Color(hex: 0xFFF3C4).opacity(night))
            pixelCircle(&context, center: CGPoint(x: center.x + p * 3, y: center.y - p * 2), radius: p * 4,
                        color: Color(rgb: colors.top).opacity(night))
        }
    }

    private func drawClouds(in context: inout GraphicsContext) {
        // 雲の色は空に合わせて変える（夕方は紫っぽく、下側がオレンジに光る）
        let body = Color(rgb: RGB(hex: 0xFFFFFF).mixed(with: colors.top, amount: 0.25 + 0.55 * night))
        let rim = Color(rgb: RGB(hex: 0xFFFFFF).mixed(with: colors.bottom, amount: 0.55))
        var rng = NoiseGenerator(seed: 7)
        for _ in 0..<5 {
            let speed = 2 + unit(&rng) * 4
            let startX = unit(&rng) * size.width
            let y = snap(horizonY * (0.12 + unit(&rng) * 0.5))
            let span = size.width + p * 40
            let raw = startX + CGFloat(seconds / 12) * speed
            let x = snap(raw.truncatingRemainder(dividingBy: span) - p * 20)
            let blocks: [(CGFloat, CGFloat, CGFloat)] = [(0, 2, 18), (3, 1, 11), (6, 0, 6), (13, 1, 4)]
            for (dx, dy, w) in blocks {
                fill(&context, CGRect(x: x + dx * p, y: y + dy * p, width: w * p, height: p * 2), body.opacity(0.9))
            }
            fill(&context, CGRect(x: x + p, y: y + p * 4, width: p * 16, height: p), rim.opacity(0.9))
        }
    }

    // MARK: 遠くの景色

    private func drawMountains(in context: inout GraphicsContext) {
        let far = Color(rgb: colors.top.mixed(with: RGB(hex: 0x1E2250), amount: 0.45))
        let near = Color(rgb: colors.top.mixed(with: RGB(hex: 0x141633), amount: 0.7))
        var x: CGFloat = 0
        while x < size.width {
            let t = Double(x / size.width)
            let farHeight = size.height * CGFloat(0.07 + 0.035 * sin(t * Double.pi * 3 + 1) + 0.02 * sin(t * 17))
            fill(&context, CGRect(x: x, y: snap(horizonY - farHeight), width: p * 2, height: snapUp(farHeight)), far)
            let nearHeight = size.height * CGFloat(0.035 + 0.025 * sin(t * Double.pi * 5 + 2))
            fill(&context, CGRect(x: x, y: snap(horizonY - nearHeight), width: p * 2, height: snapUp(nearHeight)), near)
            x += p * 2
        }
    }

    private func drawTreesAndHouses(in context: inout GraphicsContext) {
        // 地平線の木々
        let tree = color(day: 0x2F5E34, night: 0x0F1F18)
        var rng = NoiseGenerator(seed: 5)
        var x: CGFloat = 0
        while x < size.width {
            let h = snap(p * (2 + unit(&rng) * 4))
            fill(&context, CGRect(x: x, y: horizonY - h, width: p * 3, height: h), tree)
            x += p * 3
        }

        // 民家（夜は窓に明かりがつく）
        let wall = color(day: 0x8C6A4F, night: 0x2A211C)
        let roof = color(day: 0x3A3F5C, night: 0x121426)
        let window = Color(hex: 0xFFD66B).opacity(0.25 + 0.75 * night)
        for (fraction, scale) in [(0.05, 1.0), (0.17, 0.8), (0.76, 0.9), (0.88, 1.1)] as [(CGFloat, CGFloat)] {
            let unitSize = snap(p * scale).isZero ? p : snap(p * scale)
            let houseX = snap(size.width * fraction)
            let wallWidth = unitSize * 10
            let wallHeight = unitSize * 5
            let wallTop = horizonY - wallHeight
            fill(&context, CGRect(x: houseX, y: wallTop, width: wallWidth, height: wallHeight), wall)
            // 階段状の屋根
            for row in 0..<4 {
                let inset = CGFloat(3 - row) * unitSize
                fill(&context, CGRect(x: houseX - unitSize + inset, y: wallTop - CGFloat(4 - row) * unitSize,
                                      width: wallWidth + unitSize * 2 - inset * 2, height: unitSize), roof)
            }
            fill(&context, CGRect(x: houseX + unitSize * 2, y: wallTop + unitSize * 2,
                                  width: unitSize * 2, height: unitSize * 2), window)
            fill(&context, CGRect(x: houseX + unitSize * 6, y: wallTop + unitSize * 2,
                                  width: unitSize * 2, height: unitSize * 2), window)
        }
    }

    // MARK: 田んぼ・あぜ道・草

    private func drawPaddies(in context: inout GraphicsContext) {
        // 田んぼの水面（空の色が映る）
        let water = colors.bottom.mixed(with: RGB(hex: 0x2A4E7A), amount: 0.45 + 0.3 * night)
        fill(&context, CGRect(x: 0, y: horizonY, width: size.width, height: fieldBottom - horizonY), Color(rgb: water))

        let lightWater = Color(rgb: water.mixed(with: colors.top, amount: 0.25))
        let levee = color(day: 0x4F8A3C, night: 0x1B3322)
        let seedling = color(day: 0x7ACB5B, night: 0x2C5A33)

        // 手前ほど間隔が広い（遠近感）
        var y = horizonY + p
        var gap = p * 2
        var row = 0
        while y < fieldBottom {
            if row.isMultiple(of: 2) {
                fill(&context, CGRect(x: 0, y: y, width: size.width, height: p), lightWater)
            }
            if row % 4 == 3 {
                // あぜ（田んぼの区切り）
                fill(&context, CGRect(x: 0, y: y, width: size.width, height: p), levee)
            } else {
                // 苗の列
                let spacing = max(p * 3, gap * 1.4)
                let offset = row.isMultiple(of: 2) ? 0 : spacing / 2
                let seedlingHeight = gap > p * 4 ? p * 2 : p
                var x = snap(offset)
                while x < size.width {
                    fill(&context, CGRect(x: x, y: y - seedlingHeight + p, width: p, height: seedlingHeight), seedling)
                    x += snap(spacing)
                }
            }
            y += snap(gap)
            gap = min(gap * 1.18 + p * 0.2, p * 9)
            row += 1
        }
    }

    private func drawPath(in context: inout GraphicsContext) {
        // 手前から、左奥の地平線へのびる土の道
        let dirt = color(day: 0xB08A5A, night: 0x3E3326)
        let edge = color(day: 0x86673F, night: 0x2A2219)
        var y = size.height
        while y > horizonY {
            let t = Double((size.height - y) / (size.height - horizonY))
            let center = size.width * CGFloat(0.52 - 0.3 * t + 0.08 * sin(t * Double.pi))
            let width = size.width * CGFloat(0.34 * pow(1 - t, 1.4)) + p * 2
            let left = snap(center - width / 2)
            let right = snap(center + width / 2)
            fill(&context, CGRect(x: left, y: y - p, width: max(p, right - left), height: p), dirt)
            fill(&context, CGRect(x: left - p, y: y - p, width: p, height: p), edge)
            fill(&context, CGRect(x: right, y: y - p, width: p, height: p), edge)
            y -= p
        }
    }

    private func drawGrass(in context: inout GraphicsContext) {
        let grass = color(day: 0x3D7A35, night: 0x16301C)
        let tuft = color(day: 0x5FA24A, night: 0x21452A)
        fill(&context, CGRect(x: 0, y: fieldBottom, width: size.width, height: size.height - fieldBottom), grass)
        var rng = NoiseGenerator(seed: 13)
        for _ in 0..<60 {
            let x = snap(unit(&rng) * size.width)
            let y = snap(fieldBottom + unit(&rng) * (size.height - fieldBottom))
            let h = p * (1 + (unit(&rng) * 2).rounded())
            fill(&context, CGRect(x: x, y: y - h, width: p, height: h), tuft)
            fill(&context, CGRect(x: x + p, y: y - h + p, width: p, height: max(p, h - p)), tuft)
        }
    }

    private func drawPoles(in context: inout GraphicsContext) {
        // 左側の電柱と電線（手前ほど大きい）
        let pole = color(day: 0x5B3A22, night: 0x1E140D)
        let wire = Color.black.opacity(0.55)
        let poles: [(x: CGFloat, base: CGFloat, height: CGFloat, thick: CGFloat)] = [
            (0.1, 0.95, 0.52, 3), (0.27, 0.74, 0.26, 2), (0.36, 0.65, 0.12, 1),
        ]
        var previousTop: CGPoint?
        for item in poles {
            let thickness = p * item.thick
            let x = snap(size.width * item.x)
            let base = snap(size.height * item.base)
            let height = snap(size.height * item.height)
            let top = base - height
            fill(&context, CGRect(x: x, y: top, width: thickness, height: height), pole)
            // 腕木
            let armWidth = thickness * 6
            fill(&context, CGRect(x: x - armWidth / 2 + thickness / 2, y: top + thickness * 2,
                                  width: armWidth, height: max(p, thickness / 2)), pole)
            let wireStart = CGPoint(x: x + thickness / 2, y: top + thickness * 2)
            if let previousTop {
                drawWire(&context, from: previousTop, to: wireStart, color: wire)
            } else {
                // 画面の左外へのびる電線
                drawWire(&context, from: CGPoint(x: -p * 4, y: wireStart.y - p * 6), to: wireStart, color: wire)
            }
            previousTop = wireStart
        }
    }

    /// たるんだ電線を、ドットを並べて描く
    private func drawWire(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color) {
        let length = hypot(b.x - a.x, b.y - a.y)
        let steps = max(2, Int(length / p))
        let sag = length * 0.08
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = a.x + (b.x - a.x) * t
            let y = a.y + (b.y - a.y) * t + sag * 4 * t * (1 - t)
            fill(&context, CGRect(x: snap(x), y: snap(y), width: p, height: max(1, p / 2)), color)
        }
    }

    // MARK: 道具

    private func fill(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
        context.fill(Path(rect), with: .color(color))
    }

    private func pixelCircle(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        let steps = Int(radius / p)
        for row in -steps...steps {
            for column in -steps...steps where row * row + column * column <= steps * steps {
                fill(&context, CGRect(x: center.x + CGFloat(column) * p, y: center.y + CGFloat(row) * p,
                                      width: p, height: p), color)
            }
        }
    }

    /// 昼の色と夜の色を、今の暗さで混ぜる
    private func color(day: UInt32, night nightHex: UInt32) -> Color {
        Color(rgb: RGB(hex: day).mixed(with: RGB(hex: nightHex), amount: night))
    }

    private func unit(_ rng: inout NoiseGenerator) -> CGFloat {
        CGFloat((rng.next() + 1) / 2)
    }

    /// ドットの格子にそろえる
    private func snap(_ value: CGFloat) -> CGFloat {
        (value / p).rounded(.down) * p
    }

    private func snapUp(_ value: CGFloat) -> CGFloat {
        (value / p).rounded(.up) * p
    }
}

#Preview {
    SkyBackgroundView(date: Date(), calendar: .current)
        .ignoresSafeArea()
}
