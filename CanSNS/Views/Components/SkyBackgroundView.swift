import SwiftUI

/// 自販機の後ろの背景。時刻で空の色が変わり、夜は星と窓明かり、昼は太陽と雲が出る。
/// ドット絵（8bit）っぽく見えるように、四角形だけで描いている。
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

        ZStack {
            LinearGradient(colors: [Color(rgb: colors.top), Color(rgb: colors.bottom)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let pixel = max(2, (size.width / 160).rounded())
                drawStars(in: &context, size: size, pixel: pixel, night: night, seconds: seconds)
                drawSunAndMoon(in: &context, size: size, pixel: pixel, hour: hour, night: night)
                drawClouds(in: &context, size: size, pixel: pixel, night: night, seconds: seconds)
                drawCity(in: &context, size: size, pixel: pixel, night: night)
            }
        }
    }

    // MARK: - 描画

    private func unit(_ rng: inout NoiseGenerator) -> CGFloat {
        CGFloat((rng.next() + 1) / 2)
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize, pixel: CGFloat,
                           night: Double, seconds: Double) {
        guard night > 0.05 else { return }
        var rng = NoiseGenerator(seed: 42)
        for index in 0..<70 {
            let x = unit(&rng) * size.width
            let y = unit(&rng) * size.height * 0.55
            let twinkle = 0.55 + 0.45 * sin(seconds * 1.3 + Double(index))
            let side = pixel * (index.isMultiple(of: 7) ? 2 : 1)
            let rect = CGRect(x: (x / pixel).rounded() * pixel, y: (y / pixel).rounded() * pixel,
                              width: side, height: side)
            context.fill(Path(rect), with: .color(.white.opacity(night * twinkle)))
        }
    }

    private func drawSunAndMoon(in context: inout GraphicsContext, size: CGSize, pixel: CGFloat,
                                hour: Double, night: Double) {
        if night < 0.9, hour >= 5.5, hour <= 19 {
            // 太陽：朝に左から昇り、夕方に右へ沈む
            let t = (hour - 5.5) / 13.5
            let x = size.width * (0.08 + 0.84 * t)
            let y = size.height * 0.42 - CGFloat(sin(t * Double.pi)) * size.height * 0.32
            pixelCircle(in: &context, center: CGPoint(x: x, y: y), radius: pixel * 7, pixel: pixel,
                        color: Color(hex: 0xFFE27A).opacity(1 - night))
        }
        if night > 0.1 {
            // 月（右上に三日月）
            let center = CGPoint(x: size.width * 0.8, y: size.height * 0.1)
            pixelCircle(in: &context, center: center, radius: pixel * 6, pixel: pixel,
                        color: Color(hex: 0xFFF6C8).opacity(night))
            let colors = SkyPalette.colors(hour: hour)
            pixelCircle(in: &context, center: CGPoint(x: center.x + pixel * 3, y: center.y - pixel * 2),
                        radius: pixel * 5, pixel: pixel, color: Color(rgb: colors.top).opacity(night))
        }
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, pixel: CGFloat,
                            night: Double, seconds: Double) {
        let opacity = (1 - night) * 0.85
        guard opacity > 0.05 else { return }
        var rng = NoiseGenerator(seed: 7)
        for _ in 0..<4 {
            let speed = 2 + unit(&rng) * 4
            let startX = unit(&rng) * size.width
            let y = size.height * (0.08 + unit(&rng) * 0.3)
            let span = size.width + pixel * 40
            let raw = startX + CGFloat(seconds / 10) * speed
            let x = raw.truncatingRemainder(dividingBy: span) - pixel * 20
            let blocks: [(CGFloat, CGFloat, CGFloat)] = [(0, 2, 16), (3, 0, 9), (8, 1, 6)]
            for (dx, dy, w) in blocks {
                let rect = CGRect(x: x + dx * pixel, y: y + dy * pixel, width: w * pixel, height: pixel * 3)
                context.fill(Path(rect), with: .color(.white.opacity(opacity)))
            }
        }
    }

    private func drawCity(in context: inout GraphicsContext, size: CGSize, pixel: CGFloat, night: Double) {
        let groundY = size.height * 0.8
        let dayColor = RGB(hex: 0x7C8FB3)
        let nightColor = RGB(hex: 0x141836)
        let building = Color(rgb: dayColor.mixed(with: nightColor, amount: night))
        let farBuilding = Color(rgb: RGB(hex: 0xA5B6D6).mixed(with: RGB(hex: 0x20264D), amount: night))

        // 遠くのビル（うすい色）
        var rng = NoiseGenerator(seed: 3)
        var x: CGFloat = 0
        while x < size.width {
            let w = (8 + unit(&rng) * 10).rounded() * pixel
            let h = (20 + unit(&rng) * 40).rounded() * pixel
            context.fill(Path(CGRect(x: x, y: groundY - h - pixel * 10, width: w, height: h + pixel * 10)),
                         with: .color(farBuilding))
            x += w
        }

        // 手前のビル（窓つき）
        rng = NoiseGenerator(seed: 11)
        x = -pixel * 4
        while x < size.width {
            let w = (10 + unit(&rng) * 14).rounded() * pixel
            let h = (14 + unit(&rng) * 34).rounded() * pixel
            let top = groundY - h
            context.fill(Path(CGRect(x: x, y: top, width: w, height: h)), with: .color(building))
            var wy = top + pixel * 3
            while wy < groundY - pixel * 3 {
                var wx = x + pixel * 2
                while wx < x + w - pixel * 3 {
                    let lit = unit(&rng) > 0.5
                    let windowColor: Color = lit
                        ? Color(hex: 0xFFD66B).opacity(0.25 + 0.75 * night)
                        : Color.white.opacity(0.12 * (1 - night))
                    context.fill(Path(CGRect(x: wx, y: wy, width: pixel * 2, height: pixel * 2)),
                                 with: .color(windowColor))
                    wx += pixel * 4
                }
                wy += pixel * 5
            }
            x += w + pixel * 2
        }

        // 歩道と道路
        let sidewalk = Color(rgb: RGB(hex: 0xB8B2A7).mixed(with: RGB(hex: 0x3A3845), amount: night))
        let road = Color(rgb: RGB(hex: 0x5B5E6B).mixed(with: RGB(hex: 0x16171F), amount: night))
        context.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: pixel * 6)), with: .color(sidewalk))
        context.fill(Path(CGRect(x: 0, y: groundY + pixel * 6, width: size.width, height: size.height)),
                     with: .color(road))
        var lineX: CGFloat = 0
        while lineX < size.width {
            context.fill(Path(CGRect(x: lineX, y: groundY + pixel * 16, width: pixel * 8, height: pixel)),
                         with: .color(.white.opacity(0.5)))
            lineX += pixel * 16
        }
    }

    /// ドット絵風の円
    private func pixelCircle(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                             pixel: CGFloat, color: Color) {
        let steps = Int(radius / pixel)
        for row in -steps...steps {
            for column in -steps...steps where row * row + column * column <= steps * steps {
                let rect = CGRect(x: center.x + CGFloat(column) * pixel, y: center.y + CGFloat(row) * pixel,
                                  width: pixel, height: pixel)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        SkyBackgroundView(date: Date(), calendar: .current)
    }
    .ignoresSafeArea()
}
