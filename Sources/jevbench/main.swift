import Foundation
import Jev

// MARK: - Result records

struct ArmResult: Sendable {
    var sampleID: String
    var stressor: String
    var department: Department?
    var isUrgent: Bool?
    var confidence: Double?
    var seconds: Double
    /// For arm C: how much of `seconds` the on-device step took.
    var onDeviceSeconds: Double = 0
    var inputTokens: Int = 0
    /// Arm D's Jev prediction before Foundation Models makes the final call.
    var upstreamDepartment: Department? = nil
}

extension Array where Element == ArmResult {
    func accuracy(_ keyPath: KeyPath<Sample, Department>) -> Double {
        let truth = Dictionary(uniqueKeysWithValues: Dataset.samples.map { ($0.id, $0[keyPath: keyPath]) })
        let hits = count { $0.department != nil && $0.department == truth[$0.sampleID] }
        return Double(hits) / Double(count)
    }

    func urgencyAccuracy() -> Double {
        let truth = Dictionary(uniqueKeysWithValues: Dataset.samples.map { ($0.id, $0.isUrgent) })
        let hits = count { $0.isUrgent != nil && $0.isUrgent == truth[$0.sampleID] }
        return Double(hits) / Double(count)
    }

    var totalSeconds: Double { reduce(0) { $0 + $1.seconds } }
    var totalOnDeviceSeconds: Double { reduce(0) { $0 + $1.onDeviceSeconds } }
    var totalInputTokens: Int { reduce(0) { $0 + $1.inputTokens } }
}

// MARK: - Helpers

func elapsed<T>(_ body: () async throws -> T) async rethrows -> (value: T, seconds: Double) {
    let clock = ContinuousClock()
    var result: T!
    let duration = try await clock.measure { result = try await body() }
    return (result, Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18)
}

/// Jev returns a probability, not a boolean. The threshold is ours to pick.
func urgent(from probability: Probability?, threshold: Double = 0.5) -> Bool? {
    probability.map { $0.value >= threshold }
}

let pricePerInputToken = 0.042 / 1_000_000

enum BenchmarkError: Error {
    case missingJevConfidence
}

// MARK: - Arms

func runArmA(_ client: JevClient) async -> [ArmResult] {
    var results: [ArmResult] = []
    for sample in Dataset.samples {
        do {
            let (response, seconds) = try await elapsed {
                try await client.evaluate(state: sample.text, questions: Questions.all)
            }
            results.append(.init(
                sampleID: sample.id, stressor: sample.stressor,
                department: response[Questions.department],
                isUrgent: urgent(from: response[Questions.urgency]),
                confidence: response.confidence(of: Questions.department),
                seconds: seconds, inputTokens: response.usage.inputTokens
            ))
            FileHandle.standardError.write(Data("  A \(sample.id) ok\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("  A \(sample.id) FAILED: \(error)\n".utf8))
            results.append(.init(sampleID: sample.id, stressor: sample.stressor,
                                 department: nil, isUrgent: nil, confidence: nil, seconds: 0))
        }
    }
    return results
}

func runArmB() async -> [ArmResult] {
    var results: [ArmResult] = []
    for sample in Dataset.samples {
        do {
            let (routing, seconds) = try await elapsed { try await OnDevice.route(sample.text) }
            results.append(.init(
                sampleID: sample.id, stressor: sample.stressor,
                department: Department(rawValue: routing.department.rawValue),
                isUrgent: routing.needsToday,
                confidence: nil,          // the on-device model returns none
                seconds: seconds, onDeviceSeconds: seconds
            ))
            FileHandle.standardError.write(Data("  B \(sample.id) ok\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("  B \(sample.id) FAILED: \(error)\n".utf8))
            results.append(.init(sampleID: sample.id, stressor: sample.stressor,
                                 department: nil, isUrgent: nil, confidence: nil, seconds: 0))
        }
    }
    return results
}

func runArmC(_ client: JevClient) async -> (results: [ArmResult], normalized: [String: NormalizedInquiry]) {
    var results: [ArmResult] = []
    var normalized: [String: NormalizedInquiry] = [:]
    for sample in Dataset.samples {
        do {
            let (state, onDevice) = try await elapsed { try await OnDevice.normalize(sample.text) }
            normalized[sample.id] = state
            let (response, remote) = try await elapsed {
                try await client.evaluate(state: state, questions: Questions.all)
            }
            results.append(.init(
                sampleID: sample.id, stressor: sample.stressor,
                department: response[Questions.department],
                isUrgent: urgent(from: response[Questions.urgency]),
                confidence: response.confidence(of: Questions.department),
                seconds: onDevice + remote, onDeviceSeconds: onDevice,
                inputTokens: response.usage.inputTokens
            ))
            FileHandle.standardError.write(Data("  C \(sample.id) ok\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("  C \(sample.id) FAILED: \(error)\n".utf8))
            results.append(.init(sampleID: sample.id, stressor: sample.stressor,
                                 department: nil, isUrgent: nil, confidence: nil, seconds: 0))
        }
    }
    return (results, normalized)
}

func runArmD(_ client: JevClient) async -> [ArmResult] {
    var results: [ArmResult] = []
    for sample in Dataset.samples {
        do {
            let (response, remote) = try await elapsed {
                try await client.evaluate(state: sample.text, questions: Questions.all)
            }
            let initialDepartment = try response.require(Questions.department)
            let initialUrgency = try response.require(Questions.urgency)
            guard let confidence = response.confidence(of: Questions.department) else {
                throw BenchmarkError.missingJevConfidence
            }
            let (routing, onDevice) = try await elapsed {
                try await OnDevice.routeWithJev(
                    sample.text,
                    department: initialDepartment,
                    confidence: confidence,
                    probabilities: response.probabilities(of: Questions.department) ?? [:],
                    urgencyProbability: initialUrgency.value
                )
            }
            results.append(.init(
                sampleID: sample.id, stressor: sample.stressor,
                department: Department(rawValue: routing.department.rawValue),
                isUrgent: routing.needsToday, confidence: confidence,
                seconds: remote + onDevice, onDeviceSeconds: onDevice,
                inputTokens: response.usage.inputTokens,
                upstreamDepartment: initialDepartment
            ))
            FileHandle.standardError.write(Data("  D \(sample.id) ok\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("  D \(sample.id) FAILED: \(error)\n".utf8))
            results.append(.init(sampleID: sample.id, stressor: sample.stressor,
                                 department: nil, isUrgent: nil, confidence: nil, seconds: 0))
        }
    }
    return results
}

// MARK: - Reporting

func pct(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
func secs(_ value: Double) -> String { String(format: "%.2fs", value) }

func report(a: [ArmResult], b: [ArmResult], c: [ArmResult], d: [ArmResult]) {
    let n = Dataset.samples.count
    print("")
    print("=== \(n) 件の日本語問い合わせを 4 通りで振り分け ===")
    print("")
    // "Label agreement", not accuracy: the urgency labels disagree with the
    // criteria handed to the model, so the column cannot rank the arms.
    print("| 構成 | 部署の正解率 | 緊急度のラベル一致率 | 合計時間 | うちオンデバイス | 入力トークン | コスト |")
    print("|---|---|---|---|---|---|---|")
    for (label, arm) in [("A. Jev 単体（日本語のまま）", a),
                         ("B. Foundation Models 単体", b),
                         ("C. FM で英語に整形 → Jev", c),
                         ("D. Jev の判定 → FM が最終判断", d)] {
        let cost = Double(arm.totalInputTokens) * pricePerInputToken
        print("| \(label) | \(pct(arm.accuracy(\.department))) | \(pct(arm.urgencyAccuracy())) "
            + "| \(secs(arm.totalSeconds)) | \(secs(arm.totalOnDeviceSeconds)) "
            + "| \(arm.totalInputTokens) | \(cost == 0 ? "$0" : String(format: "$%.6f", cost)) |")
    }

    print("")
    print("=== 1 件あたりの平均 ===")
    print("")
    print("| 構成 | 平均レイテンシ |")
    print("|---|---|")
    for (label, arm) in [("A", a), ("B", b), ("C", c), ("D", d)] {
        print("| \(label) | \(secs(arm.totalSeconds / Double(n))) |")
    }

    print("")
    print("=== サンプルごと（× は誤り） ===")
    print("")
    print("| ID | 難所 | 正解 | A | conf | B | C | conf | D Jev | D FM | D Jev conf |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    let byID = { (arm: [ArmResult]) in Dictionary(uniqueKeysWithValues: arm.map { ($0.sampleID, $0) }) }
    let (ma, mb, mc, md) = (byID(a), byID(b), byID(c), byID(d))
    for sample in Dataset.samples {
        func cell(_ result: ArmResult?) -> String {
            guard let value = result?.department else { return "—" }
            return value == sample.department ? value.rawValue : "**\(value.rawValue)** ×"
        }
        func upstreamCell(_ result: ArmResult?) -> String {
            guard let value = result?.upstreamDepartment else { return "—" }
            return value == sample.department ? value.rawValue : "**\(value.rawValue)** ×"
        }
        func conf(_ result: ArmResult?) -> String {
            guard let value = result?.confidence else { return "—" }
            return String(format: "%.2f", value)
        }
        print("| \(sample.id) | \(sample.stressor) | \(sample.department.rawValue) "
            + "| \(cell(ma[sample.id])) | \(conf(ma[sample.id])) | \(cell(mb[sample.id])) "
            + "| \(cell(mc[sample.id])) | \(conf(mc[sample.id])) "
            + "| \(upstreamCell(md[sample.id])) | \(cell(md[sample.id])) "
            + "| \(conf(md[sample.id])) |")
    }
}

// MARK: - Entry point

guard let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !apiKey.isEmpty else {
    FileHandle.standardError.write(Data("TYPESAFE_API_KEY is not set\n".utf8))
    exit(1)
}

let client = JevClient(apiKey: apiKey)

FileHandle.standardError.write(Data("arm A: Jev on raw Japanese\n".utf8))
let a = await runArmA(client)
FileHandle.standardError.write(Data("arm B: Foundation Models alone\n".utf8))
let b = await runArmB()
FileHandle.standardError.write(Data("arm C: Foundation Models then Jev\n".utf8))
let (c, normalized) = await runArmC(client)
FileHandle.standardError.write(Data("arm D: Jev then Foundation Models\n".utf8))
let d = await runArmD(client)

report(a: a, b: b, c: c, d: d)

// Dump the normalised states so the article can show what Jev actually saw.
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
if let data = try? encoder.encode(normalized) {
    try? data.write(to: URL(fileURLWithPath: "normalized.json"))
    FileHandle.standardError.write(Data("\nwrote normalized.json\n".utf8))
}
