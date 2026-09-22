import Foundation
import FoundationModels

// MARK: - Arm C: on-device normalisation, then Jev

/// The English state Jev sees in arm C.
///
/// Every field exists to work around a documented Jev weakness: the model reads
/// English best, loses accuracy when the state carries irrelevant detail, and
/// reads dates as text rather than as ordered quantities.
@Generable
struct NormalizedInquiry: Codable, Sendable {
    @Guide(description: "What the customer wants, in one English sentence. No interpretation.")
    var request: String

    @Guide(description: "The product area involved, in English. Use 'unknown' if the text does not say.")
    var productArea: String

    @Guide(description: "Deadlines the customer states, in English, each as an ISO date or a relative phrase. Empty if none.")
    var deadlines: [String]

    @Guide(description: "Amounts, counts and durations the customer states, in English. Empty if none.")
    var figures: [String]

    @Guide(description: "Things the customer explicitly says are NOT the problem, in English. Empty if none.")
    var exclusions: [String]
}

/// Arm B: the on-device model decides on its own.
@Generable
enum FMDepartment: String, Codable, Sendable {
    case billing
    case technical
    case sales
    case account
}

@Generable
struct FMRouting: Codable, Sendable {
    @Guide(description: "The team that should handle this inquiry.")
    var department: FMDepartment

    @Guide(description: "True only if the inquiry must be handled today.")
    var needsToday: Bool
}

// MARK: - Sessions

enum OnDevice {
    static let normalizerInstructions = """
    You rewrite a Japanese customer support inquiry as English structured data.

    Translate faithfully and literally. Never add a fact the customer did not state, \
    and never soften or sharpen how urgent the text sounds. Drop personal anecdotes \
    and small talk that do not bear on the request. Do not decide which team should \
    handle it — only restate what the customer said.
    """

    static let routerInstructions = """
    You route Japanese customer support inquiries to the team that should handle them, \
    and decide whether they must be handled today.

    billing: invoices, charges, refunds, pricing on an existing contract, trial billing.
    technical: bugs, outages, errors, SDK and integration problems.
    sales: quotes for new or expanded contracts, plan upgrades, discount negotiation.
    account: login, credentials, two-factor, seats, permissions, deactivating members.

    Handle today only when the customer states a deadline within a day, or describes \
    an active outage or a lockout blocking their work.
    """

    static let routerWithJevInstructions = routerInstructions + """

    You also receive a Jev assessment of the same inquiry. Treat its probabilities
    as useful evidence, not ground truth. Check its conclusions against the original
    Japanese text and make your own final routing decision.
    """

    /// A fresh session per sample. A reused session would carry the previous
    /// inquiry in its transcript and bias the next answer.
    static func normalize(_ text: String) async throws -> NormalizedInquiry {
        let session = LanguageModelSession(instructions: normalizerInstructions)
        return try await session.respond(to: text, generating: NormalizedInquiry.self).content
    }

    static func route(_ text: String) async throws -> FMRouting {
        let session = LanguageModelSession(instructions: routerInstructions)
        return try await session.respond(to: text, generating: FMRouting.self).content
    }

    static func routeWithJev(
        _ text: String,
        department: Department,
        confidence: Double,
        probabilities: [Department: Double],
        urgencyProbability: Double
    ) async throws -> FMRouting {
        let distribution = Department.allCases.map {
            "\($0.rawValue): \(probabilities[$0] ?? 0)"
        }.joined(separator: "\n")
        let prompt = """
        Original Japanese inquiry:
        \(text)

        Jev assessment:
        department: \(department.rawValue)
        department confidence: \(confidence)
        department probabilities:
        \(distribution)
        probability that this inquiry needs handling today: \(urgencyProbability)
        """
        let session = LanguageModelSession(instructions: routerWithJevInstructions)
        return try await session.respond(to: prompt, generating: FMRouting.self).content
    }
}
