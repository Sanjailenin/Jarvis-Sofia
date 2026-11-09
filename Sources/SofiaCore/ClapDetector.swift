import Foundation

public struct ClapDetector {
    public enum Sensitivity: String, CaseIterable, Sendable {
        case low, normal, high
        var minPeak: Double { switch self { case .low: 9000; case .normal: 4500; case .high: 2200 } }
        var floorRatio: Double { switch self { case .low: 18; case .normal: 12; case .high: 8 } }
    }
    public static let blockSamples = 80
    public static let minGap: TimeInterval = 0.12
    public static let maxGap: TimeInterval = 0.8
    public static let warmup: TimeInterval = 2.0
    static let jumpRatio: Double = 3.0
    static let decayRatio: Double = 0.35
    static let decayBlocks = 16
    static let historyBlocks = 20
    static let maxAmbientRMS: Double = 900
    static let similarity: Double = 2.5
    static let dipRatio: Double = 0.25

    public var sensitivity: Sensitivity
    private var pending: [Int16] = []
    private var floor: Double = 150
    private var history: [Double] = []
    private var blockIndex = 0
    private var candidate: (block: Int, peak: Double)?
    private var first: Int?
    private var firstPeak = 0.0
    private var dipped = false
    private var lastOnset = -1_000_000

    public init(sensitivity: Sensitivity = .normal) { self.sensitivity = sensitivity }

    public mutating func feed(_ samples: [Int16]) -> Bool {
        pending.append(contentsOf: samples)
        var fired = false
        while pending.count >= Self.blockSamples {
            let block = pending.prefix(Self.blockSamples)
            pending.removeFirst(Self.blockSamples)
            var peak = 0.0, acc = 0.0
            for s in block { let d = abs(Double(s)); peak = max(peak, d); acc += d * d }
            if process(peak: peak, rms: sqrt(acc / Double(block.count))) { fired = true }
        }
        return fired
    }

    private mutating func process(peak: Double, rms: Double) -> Bool {
        defer { blockIndex += 1; history.append(peak); if history.count > Self.historyBlocks { history.removeFirst() } }
        let perSecond = 16000.0 / Double(Self.blockSamples)
        let warm = Double(blockIndex) / perSecond >= Self.warmup
        var fired = false

        if let c = candidate {
            let age = blockIndex - c.block
            if peak <= c.peak * Self.decayRatio {
                candidate = nil
                fired = confirm(c.block, peak: c.peak)
            } else if age >= Self.decayBlocks {
                candidate = nil
            }
        }
        let recent = history.isEmpty ? 0 : history.reduce(0, +) / Double(history.count)
        let threshold = max(sensitivity.minPeak, floor * sensitivity.floorRatio)
        if warm, candidate == nil, floor <= Self.maxAmbientRMS, peak > threshold, peak > recent * Self.jumpRatio, blockIndex - lastOnset > 10 {
            candidate = (blockIndex, peak)
            lastOnset = blockIndex
        }
        if first != nil, candidate == nil, peak < firstPeak * Self.dipRatio { dipped = true }
        if let f = first, Double(blockIndex - f) / perSecond > Self.maxGap { first = nil }
        if peak < threshold { floor = max(40, floor * 0.985 + rms * 0.015) }
        return fired
    }

    private mutating func confirm(_ block: Int, peak: Double) -> Bool {
        let perSecond = 16000.0 / Double(Self.blockSamples)
        if let f = first {
            let gap = Double(block - f) / perSecond
            let alike = peak / firstPeak <= Self.similarity && firstPeak / peak <= Self.similarity
            if gap >= Self.minGap && gap <= Self.maxGap && alike && dipped { first = nil; dipped = false; return true }
        }
        first = block; firstPeak = peak; dipped = false
        return false
    }
}
