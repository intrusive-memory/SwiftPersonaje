import Foundation
import SwiftPersonaje

/// One character's metrics. A `nil` metric was not scored: its fixture isn't
/// filled in yet, or there was nothing to score.
public struct CharacterScores: Sendable, Equatable, Codable {
  public let member: String
  public let fixtureComplete: Bool
  public let chunks: Int
  public let chunkFailures: Int
  /// The summarizer's error, when it threw.
  public let summaryFailure: String?
  public let extractedFacts: Int
  public let verifiedFacts: Int
  /// Verified over extracted.
  public let quoteVerificationRate: Double?
  /// Verified facts matching a gold or acceptable fact, over verified facts.
  public let precision: Double?
  /// Gold facts matched by a verified fact, over gold facts.
  public let recall: Double?
  /// IDs of the `must-not-say` claims the facts or the summary made.
  public let hallucinations: [String]?
  /// Supported summary sentences over summary sentences.
  public let summaryTraceability: Double?
  /// Sentences of the hand-written summary that the run's verified facts
  /// support, over its sentences. Informational; no threshold.
  public let goldSummaryCoverage: Double?
  /// Verified facts matching no gold or acceptable fact: candidates to
  /// review and add to `acceptable:`.
  public let unmatchedFactIDs: [String]
  /// Gold facts no verified fact matched.
  public let missedGoldFactIDs: [String]
  /// Gold facts whose own quotes don't verify against the episodes: a typo
  /// or a wrong scene in the fixture.
  public let invalidGoldFactIDs: [String]
}

/// Scores a run against a fixture. Deterministic: no model.
///
/// ## Matching a fact to a gold fact
///
/// Two facts match when they cite the same scene and their quotes overlap:
/// after normalization (``QuoteText/normalize(_:)``, lowercased), one quote
/// contains the other, or their word sets have a Jaccard similarity of at
/// least ``quoteOverlap``. Statements aren't compared; the quote is the
/// evidence, and it's the part a check can rely on.
///
/// ## Hallucinations
///
/// A `must-not-say` claim is made when any of its phrases appears,
/// case-insensitively, in a verified fact's statement or in the summary.
public enum EvalScoring {

  public static let quoteOverlap = 0.5

  public static func score(
    _ run: CharacterSummaryRun, against fixture: CharacterFixture, verifier: QuoteVerifier
  ) -> CharacterScores {
    let invalidGold = fixture.facts.filter {
      !verifier.verify($0.quote, at: $0.citation).isVerified
    }
    let reference = fixture.facts + fixture.acceptable
    let unmatched = run.verifiedFacts.filter { fact in
      !reference.contains { matches(fact, $0) }
    }
    let missed = fixture.facts.filter { gold in
      !run.verifiedFacts.contains { matches($0, gold) }
    }

    let complete = fixture.isComplete
    let precision: Double? =
      complete && !run.verifiedFacts.isEmpty
      ? Double(run.verifiedFacts.count - unmatched.count) / Double(run.verifiedFacts.count) : nil
    let recall: Double? =
      complete ? Double(fixture.facts.count - missed.count) / Double(fixture.facts.count) : nil
    let hallucinations: [String]? =
      complete ? forbiddenClaims(in: run, fixture.forbidden).map(\.id) : nil
    let coverage: Double? =
      complete && !fixture.summary.isEmpty
      ? SummaryTraceability.check(
        text: fixture.summary, member: fixture.member, facts: run.verifiedFacts
      ).rate : nil

    return CharacterScores(
      member: run.member, fixtureComplete: complete, chunks: run.chunks.count,
      chunkFailures: run.chunkFailures.count, summaryFailure: run.summaryFailure,
      extractedFacts: run.extractedFacts.count,
      verifiedFacts: run.verifiedFacts.count, quoteVerificationRate: run.quoteVerificationRate,
      precision: precision, recall: recall, hallucinations: hallucinations,
      summaryTraceability: run.traceability?.rate, goldSummaryCoverage: coverage,
      unmatchedFactIDs: complete ? unmatched.map(\.id) : [],
      missedGoldFactIDs: complete ? missed.map(\.id) : [],
      invalidGoldFactIDs: complete ? invalidGold.map(\.id) : [])
  }

  public static func matches(_ fact: CharacterFact, _ gold: GoldFact) -> Bool {
    guard fact.citation == gold.citation else { return false }
    let a = QuoteText.normalize(fact.quote).lowercased()
    let b = QuoteText.normalize(gold.quote).lowercased()
    guard !a.isEmpty, !b.isEmpty else { return false }
    if a.contains(b) || b.contains(a) { return true }
    let wordsA = words(a)
    let wordsB = words(b)
    let union = wordsA.union(wordsB)
    guard !union.isEmpty else { return false }
    return Double(wordsA.intersection(wordsB).count) / Double(union.count) >= quoteOverlap
  }

  public static func forbiddenClaims(in run: CharacterSummaryRun, _ claims: [ForbiddenClaim])
    -> [ForbiddenClaim]
  {
    let texts = (run.verifiedFacts.map(\.statement) + [run.summary?.text ?? ""])
      .map { $0.lowercased() }
    return claims.filter { claim in
      claim.phrases.contains { phrase in
        let needle = phrase.lowercased()
        return !needle.isEmpty && texts.contains { $0.contains(needle) }
      }
    }
  }

  static func words(_ text: String) -> Set<String> {
    Set(text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init))
  }
}
