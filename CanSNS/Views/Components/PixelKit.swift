import CoreText
import SwiftUI

// MARK: - ドットフォント

/// ドット絵の世界観に合わせるための、日本語対応のドットフォント（DotGothic16 / OFL ライセンス）。
/// フォントファイルが見つからないときは、自動でふつうのシステムフォントになる。
enum PixelFont {
    static let name = "DotGothic16-Regular"

    /// アプリ起動時に1回だけ呼ぶ（Info.plist に書かなくても使えるように登録する）
    static func register() {
        guard let url = Bundle.main.url(forResource: "DotGothic16-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    /// ドットフォント。`fixed` を true にすると、文字サイズの設定に合わせて大きくならない（自販機の中の小さい文字用）
    static func pixel(_ size: CGFloat, fixed: Bool = false) -> Font {
        fixed ? .custom(PixelFont.name, fixedSize: size) : .custom(PixelFont.name, size: size)
    }
}

// MARK: - 8bit の色

enum Pixel {
    /// RPG のメッセージウィンドウの色
    static let windowFill = Color(hex: 0x14163A)
    static let windowBorder = Color(hex: 0xF4F1E4)
    static let ink = Color(hex: 0x111111)
    static let cream = Color(hex: 0xFFF6DA)
    static let yellow = Color(hex: 0xFFD23F)
    static let green = Color(hex: 0x3BB273)
    static let blue = Color(hex: 0x2F6FDB)
    static let gray = Color(hex: 0x8A8FA3)
}

// MARK: - 角がカクカクの四角形

/// 角を階段状に欠いた四角形（ドット絵のウィンドウやボタンの形）
struct PixelBox: Shape {
    /// 角の欠け具合（1段の大きさ）
    var step: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let s = min(step, rect.width / 4, rect.height / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        path.closeSubpath()
        return path
    }
}

/// ドット絵の枠：外側の縁の色 → 内側の塗り、の順に重ねて描く
struct PixelFrame: View {
    var fill: Color
    var border: Color
    var borderWidth: CGFloat = 3
    var step: CGFloat = 3
    /// 右下にずらした影（ぼかさない、ドット絵らしい影）
    var shadow: Color? = nil
    var shadowOffset: CGFloat = 4

    var body: some View {
        ZStack {
            if let shadow {
                PixelBox(step: step)
                    .fill(shadow)
                    .offset(x: shadowOffset, y: shadowOffset)
            }
            PixelBox(step: step)
                .fill(border)
            PixelBox(step: max(1, step - 1))
                .fill(fill)
                .padding(borderWidth)
        }
    }
}

extension View {
    /// RPG のメッセージウィンドウ風の枠（夜空の上でも読みやすい）
    func pixelWindow(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PixelFrame(fill: Pixel.windowFill.opacity(0.94), border: Pixel.windowBorder,
                           borderWidth: 3, step: 4, shadow: .black.opacity(0.35))
            )
            .foregroundStyle(Pixel.windowBorder)
    }

    /// 明るい紙のような枠（冷蔵庫の中など、明るい場所用）
    func pixelPaper(fill: Color = Pixel.cream, border: Color = Pixel.ink, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PixelFrame(fill: fill, border: border, borderWidth: 3, step: 4, shadow: .black.opacity(0.2))
            )
            .foregroundStyle(Pixel.ink)
    }
}

// MARK: - ドット絵のボタン

/// 押すと少し沈む、ドット絵のボタン
struct PixelButtonStyle: ButtonStyle {
    var color: Color = Theme.machineBody
    var textColor: Color = .white
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        PixelButtonBody(configuration: configuration, color: color, textColor: textColor, fontSize: fontSize)
    }

    private struct PixelButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let textColor: Color
        let fontSize: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.pixel(fontSize))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(
                    PixelFrame(fill: color, border: Pixel.ink, borderWidth: 3, step: 3,
                               shadow: pressed ? nil : .black.opacity(0.45), shadowOffset: 4)
                )
                .overlay(alignment: .top) {
                    // 上のふちの光（ドット絵のハイライト）
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 3)
                        .padding(.horizontal, 9)
                        .padding(.top, 6)
                }
                .offset(y: pressed ? 3 : 0)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

/// ドット絵風の入力欄
struct PixelTextField: View {
    var placeholder: String
    @Binding var text: String
    var monospaced: Bool = false

    var body: some View {
        // 入力欄は白で固定なので、ダークモードでも例文が読めるように色を決めておく
        TextField(text: $text, prompt: Text(placeholder).foregroundColor(Pixel.ink.opacity(0.45))) {
            Text(placeholder)
        }
            .font(monospaced ? .pixel(22) : .pixel(17))
            .foregroundStyle(Pixel.ink)
            .tint(Pixel.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(PixelFrame(fill: .white, border: Pixel.ink, borderWidth: 3, step: 3))
    }
}

/// 2つのうちどちらかを選ぶ、ドット絵のタブ
struct PixelTabs<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    selection = option.value
                    SoundPlayer.shared.play(.tick)
                } label: {
                    Text(option.title)
                        .font(.pixel(15))
                        .foregroundStyle(selected ? Color.white : Pixel.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            PixelFrame(fill: selected ? Pixel.blue : Color.white, border: Pixel.ink,
                                       borderWidth: 3, step: 3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// ウィンドウの見出し（★ 見出し）
struct PixelHeading: View {
    var text: String
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 6) {
            Text("★")
                .font(.pixel(size * 0.8, fixed: true))
                .foregroundStyle(Pixel.yellow)
                .accessibilityHidden(true)
            Text(text)
                .font(.pixel(size))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// ドット絵の文字のふち取り（上下左右に1ドットずつ影を置く）。明るい空の上でも文字が読める。
    func pixelOutline(_ color: Color = Pixel.ink, width: CGFloat = 1.5) -> some View {
        self
            .shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: width)
            .shadow(color: color, radius: 0, x: 0, y: -width)
    }
}
