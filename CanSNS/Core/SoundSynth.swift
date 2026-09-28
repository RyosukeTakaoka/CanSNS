import Foundation

/// アプリで鳴らす効果音の種類
enum SoundEffect: String, CaseIterable {
    /// 商品ボタンを押した「ピッ」
    case beep
    /// 缶が落ちる「ガコン！」
    case gakon
    /// 缶を開ける「プシュッ！」
    case pshu
    /// ルーレットの数字が回る「カチッ」
    case tick
    /// ルーレットで4つそろった「あたり！」
    case win
}

/// 効果音を「計算で」作る。音声ファイルを用意しなくても鳴らせる。
/// 出力は 16bit / モノラル の WAV データ。
enum SoundSynth {
    static let sampleRate = 44_100
    private static let twoPi = 2 * Double.pi

    static func wavData(for effect: SoundEffect) -> Data {
        wavData(samples: samples(for: effect))
    }

    static func samples(for effect: SoundEffect) -> [Float] {
        switch effect {
        case .beep: return tone(frequency: 1760, duration: 0.09, gain: 0.5)
        case .tick: return click()
        case .gakon: return gakon()
        case .pshu: return pshu()
        case .win: return fanfare()
        }
    }

    // MARK: - 各効果音

    private static func gakon() -> [Float] {
        let sr = Double(sampleRate)
        let count = Int(0.6 * sr)
        var out = [Float](repeating: 0, count: count)
        var rng = NoiseGenerator(seed: 7)

        // 「ドン」という低い音＋「ガッ」というノイズを、少しずらして2回（缶が跳ねる感じ）
        for (start, gain) in [(0.0, 1.0), (0.11, 0.45)] {
            let s0 = Int(start * sr)
            for i in s0..<count {
                let t = Double(i - s0) / sr
                let low = sin(twoPi * 58 * t) * exp(-t * 13)
                let knock = Double(rng.next()) * exp(-t * 55)
                out[i] += Float(gain * (0.9 * low + 0.7 * knock))
            }
        }
        // 金属っぽい「カーン」という響き
        for i in 0..<count {
            let t = Double(i) / sr
            let partial1 = sin(twoPi * 740 * t)
            let partial2 = 0.6 * sin(twoPi * 1130 * t)
            let ring = (partial1 + partial2) * exp(-t * 9)
            out[i] += Float(0.16 * ring)
        }
        return normalized(out)
    }

    private static func pshu() -> [Float] {
        let sr = Double(sampleRate)
        let count = Int(1.0 * sr)
        var out = [Float](repeating: 0, count: count)
        var rng = NoiseGenerator(seed: 21)
        var previous: Float = 0

        for i in 0..<count {
            let t = Double(i) / sr
            let noise = rng.next()
            // 差分をとって高い音を強調（「シュッ」という息の音）
            let hiss = (noise - previous) * 0.8 + noise * 0.2
            previous = noise
            let attack = min(1, t / 0.004)
            let body = attack * exp(-t * 5.5)
            // あとから「しゅわしゅわ」と泡がはじける音
            var bubble: Float = 0
            if t > 0.12 && rng.next() > 0.993 {
                bubble = rng.next() * Float(exp(-t * 2.5))
            }
            out[i] = hiss * Float(body) + bubble * 0.6
        }
        return normalized(out)
    }

    private static func click() -> [Float] {
        let sr = Double(sampleRate)
        let count = Int(0.025 * sr)
        return (0..<count).map { i in
            let t = Double(i) / sr
            let wave = sin(twoPi * 2600 * t)
            return Float(wave * exp(-t * 180) * 0.5)
        }
    }

    private static func fanfare() -> [Float] {
        // ドミソド〜
        let notes: [(Double, Double)] = [(523.25, 0.11), (659.25, 0.11), (783.99, 0.11), (1046.5, 0.35)]
        var out: [Float] = []
        for (frequency, duration) in notes {
            out += tone(frequency: frequency, duration: duration, gain: 0.45, harmonic: 0.3)
        }
        return out
    }

    private static func tone(frequency: Double, duration: Double, gain: Double, harmonic: Double = 0) -> [Float] {
        let sr = Double(sampleRate)
        let count = Int(duration * sr)
        let fade = 0.006
        return (0..<count).map { i in
            let t = Double(i) / sr
            let envelope = min(1, t / fade, (duration - t) / fade)
            let fundamental = sin(twoPi * frequency * t)
            let overtone = harmonic * sin(twoPi * frequency * 3 * t)
            let wave = fundamental + overtone
            return Float(wave * gain * max(0, envelope))
        }
    }

    private static func normalized(_ samples: [Float], peak: Float = 0.9) -> [Float] {
        let maxValue = samples.map { abs($0) }.max() ?? 0
        guard maxValue > 0 else { return samples }
        let scale = peak / maxValue
        return samples.map { $0 * scale }
    }

    // MARK: - WAV 形式に変換

    static func wavData(samples: [Float]) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)                              // fmt チャンクの大きさ
        append(UInt16(1), to: &data)                               // PCM
        append(UInt16(1), to: &data)                               // モノラル
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * bytesPerSample), to: &data)     // 1秒あたりのバイト数
        append(UInt16(bytesPerSample), to: &data)
        append(UInt16(16), to: &data)                              // 16bit
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize), to: &data)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(Int16(clamped * Float(Int16.max)), to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

/// 毎回同じ音になるように、種（seed）から決まるノイズを作る
struct NoiseGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1
    }

    /// -1〜1 のランダムな値
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = UInt32(truncatingIfNeeded: state >> 33)
        return Float(value) / Float(UInt32.max >> 1) * 2 - 1
    }
}
