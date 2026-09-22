import AVFoundation
import Observation
import UIKit

// MARK: - Réglages

/// Vitesse du replay des actions : cinématique, accélérée, ou coupée (état final direct).
nonisolated enum DuelFxSpeed: String, CaseIterable, Identifiable, Sendable {
    case normal, fast, off
    var id: String { rawValue }

    func scaled(_ ms: Int) -> Int {
        switch self {
        case .normal: ms
        case .fast: Int(Double(ms) * 0.45)
        case .off: 0
        }
    }
}

/// Son et vitesse des animations du duel (mémorisés sur l'appareil).
@Observable
final class DuelFxSettings {
    static let shared = DuelFxSettings()

    var sound: Bool {
        didSet { UserDefaults.standard.set(sound, forKey: "duel.fx.sound") }
    }
    var speed: DuelFxSpeed {
        didSet { UserDefaults.standard.set(speed.rawValue, forKey: "duel.fx.speed") }
    }

    private init() {
        let defaults = UserDefaults.standard
        sound = defaults.object(forKey: "duel.fx.sound") as? Bool ?? true
        speed = defaults.string(forKey: "duel.fx.speed").flatMap(DuelFxSpeed.init(rawValue:))
            ?? (UIAccessibility.isReduceMotionEnabled ? .fast : .normal)
    }
}

// MARK: - Timeline

nonisolated enum DuelSfx: Hashable, Sendable {
    case draw, summon, special, set, activate, negate, attack, damage, recover, phase, turn, coin, move, win, lose, select
}

/// Ce que le replay fait d'un événement : durée à l'écran, bruitage, secousse.
nonisolated struct DuelBeat: Sendable {
    let duration: Int
    let sfx: DuelSfx?
    let shake: Bool

    init(_ event: DuelEvent) {
        let (duration, sfx, shake) = Self.values(event)
        self.duration = duration
        self.sfx = sfx
        self.shake = shake
    }

    private static func values(_ event: DuelEvent) -> (Int, DuelSfx?, Bool) {
        switch event.kind {
        case .turn: return (1300, .turn, false)
        case .phase(let phase): return phase == .draw || phase == .standby ? (0, nil, false) : (420, .phase, false)
        case .draw(let player, _, _): return (player == 0 ? 380 : 220, .draw, false)
        case .summon(_, _, let how): return how == "SPECIAL" ? (1300, .special, false) : (1100, .summon, false)
        case .set: return (450, .set, false)
        case .activate: return (1250, .activate, false)
        case .chainNegated: return (850, .negate, false)
        case .move(_, _, let to): return to == .grave || to == .banished ? (560, .move, false) : (0, nil, false)
        case .attack: return (950, .attack, false)
        case .damage(_, let amount, let cost): return cost ? (600, .move, false) : (950, .damage, amount >= 500)
        case .recover: return (750, .recover, false)
        case .coin, .dice: return (1100, .coin, false)
        case .win, .unknown: return (0, nil, false)
        }
    }
}

// MARK: - Retours haptiques

enum DuelHaptics {
    static func play(_ event: DuelEvent) {
        switch event.kind {
        case .turn: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        case .summon(_, _, let how): UIImpactFeedbackGenerator(style: how == "SPECIAL" ? .heavy : .medium).impactOccurred()
        case .activate: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .chainNegated: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .attack: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .damage(let player, let amount, let cost) where !cost:
            if player == 0 && amount >= 1000 {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: player == 0 ? 1 : 0.6)
            }
        case .draw, .set: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        default: break
        }
    }

    static func result(won: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(won ? .success : .error)
    }
}

// MARK: - Bruitages

/// Bruitages synthétisés (aucun fichier son) : des notes et des souffles filtrés, calculés
/// une fois hors du fil principal, puis joués par un petit groupe de lecteurs. Catégorie
/// « ambient » : respecte le mode silencieux et se mélange à ta musique.
final class DuelSound {
    static let shared = DuelSound()

    private static let sampleRate = 44_100.0
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: DuelSound.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [DuelSfx: AVAudioPCMBuffer] = [:]
    private var samples: [DuelSfx: [Float]] = [:]
    private var next = 0
    private var started = false

    private init() {}

    func play(_ sfx: DuelSfx) {
        guard DuelFxSettings.shared.sound, start(), let buffer = buffer(sfx) else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        // Sans effet si le lecteur tourne déjà ; le relance après une coupure du moteur
        player.play()
    }

    private func buffer(_ sfx: DuelSfx) -> AVAudioPCMBuffer? {
        if let cached = buffers[sfx] { return cached }
        let data = samples[sfx] ?? Synth.render(Synth.voices(sfx), rate: Self.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(data.count)
        for i in 0..<data.count { channel[i] = data[i] }
        buffers[sfx] = buffer
        return buffer
    }

    private func start() -> Bool {
        if started { return engine.isRunning || (try? engine.start()) != nil }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.7
        do {
            try engine.start()
        } catch {
            return false
        }
        started = true
        // Tous les bruitages sont calculés d'avance, hors du fil principal
        Task {
            let rendered = await Task.detached(priority: .utility) { Synth.renderAll(rate: DuelSound.sampleRate) }.value
            self.samples.merge(rendered) { current, _ in current }
        }
        return true
    }
}

/// Synthèse des bruitages : fonctions pures, utilisables hors du fil principal.
nonisolated enum Synth {
    enum Wave: Sendable { case sine, triangle, saw, square }

    enum Voice: Sendable {
        case tone(freq: Double, at: Double = 0, dur: Double = 0.2, wave: Wave = .sine, gain: Double = 0.3, to: Double? = nil, attack: Double = 0.005)
        case noise(at: Double = 0, dur: Double = 0.3, from: Double = 400, to: Double = 3000, gain: Double = 0.25, q: Double = 1.2)
    }

    static let all: [DuelSfx] = [.draw, .summon, .special, .set, .activate, .negate, .attack, .damage, .recover, .phase, .turn, .coin, .move, .win, .lose, .select]

    static func renderAll(rate: Double) -> [DuelSfx: [Float]] {
        var out: [DuelSfx: [Float]] = [:]
        for sfx in all { out[sfx] = render(voices(sfx), rate: rate) }
        return out
    }

    static func note(_ semitones: Double) -> Double { 440 * pow(2, semitones / 12) }

    /// Arpège : une note par demi-ton donné, décalées de `step` secondes.
    static func arpeggio(_ semitones: [Double], base: Double, start: Double = 0, step: Double, dur: Double,
                         wave: Wave = .triangle, gain: Double, lastDur: Double? = nil) -> [Voice] {
        var out: [Voice] = []
        for (i, n) in semitones.enumerated() {
            let isLast = i == semitones.count - 1
            let length = isLast ? (lastDur ?? dur) : dur
            out.append(.tone(freq: note(n + base), at: start + Double(i) * step, dur: length, wave: wave, gain: gain))
        }
        return out
    }

    static func voices(_ sfx: DuelSfx) -> [Voice] {
        switch sfx {
        case .draw:
            return [.noise(dur: 0.12, from: 2500, to: 6000, gain: 0.12, q: 3), .tone(freq: 1400, dur: 0.05, wave: .triangle, gain: 0.08)]
        case .select:
            return [.tone(freq: 880, dur: 0.06, wave: .triangle, gain: 0.08)]
        case .phase:
            return [.tone(freq: 660, dur: 0.08, wave: .triangle, gain: 0.07), .tone(freq: 990, at: 0.05, dur: 0.1, wave: .triangle, gain: 0.05)]
        case .set:
            return [.noise(dur: 0.15, from: 300, to: 120, gain: 0.25, q: 0.8), .tone(freq: 110, dur: 0.15, gain: 0.25, to: 70)]
        case .summon:
            return [
                .noise(dur: 0.35, from: 300, to: 4000, gain: 0.18),
                .tone(freq: note(3), at: 0.2, dur: 0.35, wave: .triangle, gain: 0.18),
                .tone(freq: note(10), at: 0.28, dur: 0.5, wave: .triangle, gain: 0.14),
            ]
        case .special:
            let base: [Voice] = [
                .noise(dur: 0.5, from: 200, to: 6000, gain: 0.22),
                .tone(freq: note(-21), at: 0.25, dur: 0.8, wave: .saw, gain: 0.05),
            ]
            return base + arpeggio([0, 4, 7, 12], base: 3, start: 0.25, step: 0.07, dur: 0.6, gain: 0.13)
        case .activate:
            let base: [Voice] = [.noise(dur: 0.3, from: 4000, to: 9000, gain: 0.06, q: 4)]
            return base + arpeggio([0, 7, 12, 19], base: 12, step: 0.045, dur: 0.25, wave: .sine, gain: 0.1)
        case .negate:
            return [.tone(freq: 420, dur: 0.45, wave: .saw, gain: 0.12, to: 90), .noise(dur: 0.3, from: 1200, to: 200, gain: 0.2)]
        case .attack:
            return [
                .noise(dur: 0.28, from: 600, to: 5000, gain: 0.25),
                .noise(at: 0.22, dur: 0.18, from: 800, to: 150, gain: 0.35, q: 0.7),
                .tone(freq: 90, at: 0.22, dur: 0.25, gain: 0.35, to: 45),
            ]
        case .damage:
            return [
                .tone(freq: 70, dur: 0.45, gain: 0.45, to: 35),
                .noise(dur: 0.25, from: 500, to: 100, gain: 0.3, q: 0.6),
                .tone(freq: note(-2), at: 0.05, dur: 0.4, wave: .square, gain: 0.05, to: note(-14)),
            ]
        case .recover:
            return arpeggio([0, 5, 9, 12], base: 0, step: 0.06, dur: 0.3, wave: .sine, gain: 0.12)
        case .move:
            return [.noise(dur: 0.22, from: 3000, to: 400, gain: 0.12)]
        case .coin:
            return [.tone(freq: 2100, dur: 0.5, wave: .triangle, gain: 0.1), .tone(freq: 3150, at: 0.03, dur: 0.4, gain: 0.06)]
        case .turn:
            return [
                .noise(dur: 0.4, from: 200, to: 2000, gain: 0.08),
                .tone(freq: 196, dur: 1.6, gain: 0.18, attack: 0.01),
                .tone(freq: 392, dur: 1.3, gain: 0.09, attack: 0.01),
                .tone(freq: 588, dur: 1.0, gain: 0.06, attack: 0.01),
            ]
        case .win:
            let base: [Voice] = [.tone(freq: note(-9), at: 0.54, dur: 1.4, wave: .saw, gain: 0.05)]
            return base + arpeggio([0, 4, 7, 12, 16, 19, 24], base: 3, step: 0.09, dur: 0.35, gain: 0.14, lastDur: 1.4)
        case .lose:
            return arpeggio([0, -3, -7, -12], base: -5, step: 0.22, dur: 0.6, gain: 0.12)
        }
    }

    static func render(_ voices: [Voice], rate: Double) -> [Float] {
        var end = 0.1
        for voice in voices {
            switch voice {
            case .tone(_, let at, let dur, _, _, _, _): end = Swift.max(end, at + dur)
            case .noise(let at, let dur, _, _, _, _): end = Swift.max(end, at + dur)
            }
        }
        let count = Int((end + 0.05) * rate)
        var samples = [Float](repeating: 0, count: count)
        var seed: UInt32 = 0x9E37_79B9

        for voice in voices {
            switch voice {
            case .tone(let freq, let at, let dur, let wave, let gain, let to, let attack):
                var phase = 0.0
                let start = Int(at * rate)
                let length = Int(dur * rate)
                let decay = log(0.0001 / gain) / Swift.max(dur - attack, 0.001)
                for i in 0..<length where start + i < count {
                    let t = Double(i) / rate
                    let f = to.map { freq * pow($0 / freq, t / dur) } ?? freq
                    phase += f / rate
                    let p = phase - floor(phase)
                    let value: Double
                    switch wave {
                    case .sine: value = sin(2 * .pi * p)
                    case .triangle: value = 1 - 4 * abs(p - 0.5)
                    case .saw: value = 2 * p - 1
                    case .square: value = p < 0.5 ? 1 : -1
                    }
                    let env = t < attack ? gain * t / attack : gain * exp(decay * (t - attack))
                    samples[start + i] += Float(value * env)
                }
            case .noise(let at, let dur, let from, let to, let gain, let q):
                // Passe-bande (biquad) dont la fréquence glisse de `from` à `to`
                var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
                let start = Int(at * rate)
                let length = Int(dur * rate)
                let rise = dur * 0.3
                let decay = log(0.0001 / gain) / (dur - rise)
                for i in 0..<length where start + i < count {
                    let t = Double(i) / rate
                    let f = from * pow(to / from, t / dur)
                    let w0 = 2 * .pi * f / rate
                    let alpha = sin(w0) / (2 * q)
                    let c = 2 * cos(w0)
                    seed ^= seed << 13
                    seed ^= seed >> 17
                    seed ^= seed << 5
                    let x0 = Double(seed) / Double(UInt32.max) * 2 - 1
                    let y0 = (alpha * (x0 - x2) + c * y1 - (1 - alpha) * y2) / (1 + alpha)
                    x2 = x1
                    x1 = x0
                    y2 = y1
                    y1 = y0
                    let env = t < rise ? gain * t / rise : gain * exp(decay * (t - rise))
                    samples[start + i] += Float(y0 * env * 3)
                }
            }
        }
        // Saturation douce : jamais de clipping
        for i in 0..<count { samples[i] = tanhf(samples[i]) }
        return samples
    }
}
