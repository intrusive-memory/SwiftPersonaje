import Foundation
import PersonajeEvalKit
import SwiftPersonaje
import Testing

/// Scoring and fixture loading, with no model. These run with
/// `make test-eval` whether or not Apple Intelligence is on.
@Suite("Evaluation scoring and fixtures (no model)")
struct EvalScoringTests {

  static let lamp = "01-the-lamp.fountain"
  static let letter = "02-the-letter.fountain"
  static let fixtures = EvalConfiguration.exampleProject
    .appendingPathComponent("evals/character-summaries", isDirectory: true)

  func corpus() async throws -> EvidenceCorpus {
    let configuration = try EvalConfiguration.fromEnvironment([:])
    return try await EvidenceCorpus.load(screenplays: configuration.episodes())
  }

  func fact(_ id: String, _ statement: String, _ quote: String, _ episode: String, _ scene: String)
    -> CharacterFact
  {
    CharacterFact(
      id: id, statement: statement, quote: quote,
      citation: SceneCitation(episode: episode, scene: scene))
  }

  func run(_ facts: [CharacterFact], summary: String) -> CharacterSummaryRun {
    let summary = CharacterSummary(
      member: "WREN", sentences: [SummarySentence(text: summary, factIDs: facts.map(\.id))])
    return CharacterSummaryRun(
      member: "WREN", chunks: [], extractedFacts: facts, verifiedFacts: facts, droppedFacts: [],
      chunkFailures: [], summary: summary,
      traceability: SummaryTraceability.check(summary, facts: facts))
  }

  @Test("The example fixture loads, and is complete")
  func exampleFixtureLoads() throws {
    let fixtures = try GoldFixtures.load(from: Self.fixtures)
    #expect(fixtures.map(\.member) == ["WREN"])
    let wren = try #require(fixtures.first)
    #expect(wren.facts.map(\.id) == ["g1", "g2", "g3"])
    #expect(wren.forbidden.map(\.id) == ["m1", "m2", "m3"])
    #expect(wren.summary.hasPrefix("Wren, an older woman"))
    #expect(wren.isComplete)
  }

  @Test("Every gold quote in the example verifies against its scene")
  func exampleGoldQuotesVerify() async throws {
    let verifier = QuoteVerifier(corpus: try await corpus())
    let wren = try #require(try GoldFixtures.load(from: Self.fixtures).first)
    for gold in wren.facts {
      #expect(verifier.verify(gold.quote, at: gold.citation).isVerified, "\(gold.id)")
    }
  }

  @Test("PERSONAJE_EVAL_EPISODES picks which episode files are read")
  func episodePattern() throws {
    let all = try EvalConfiguration.fromEnvironment([:]).episodes()
    #expect(all.map(\.lastPathComponent) == [Self.lamp, Self.letter])
    let one = try EvalConfiguration.fromEnvironment(["PERSONAJE_EVAL_EPISODES": "01-*.fountain"])
    #expect(try one.episodes().map(\.lastPathComponent) == [Self.lamp])
  }

  @Test("A fixture with a TODO marker is not complete")
  func todoMarksIncomplete() {
    let fixture = CharacterFixture(
      member: "X",
      facts: [GoldFact(id: "g1", statement: "TODO", quote: "TODO", episode: "TODO", scene: nil)],
      acceptable: [], summary: "TODO", forbidden: [])
    #expect(!fixture.isComplete)
  }

  @Test("Precision, recall and hallucinations against the example fixture")
  func scoring() async throws {
    let corpus = try await corpus()
    let wren = try #require(try GoldFixtures.load(from: Self.fixtures).first)
    let facts = [
      // Matches g2 (quote contained in the gold quote).
      fact("f1", "Wren counts.", "I count.", Self.lamp, "1"),
      // Matches g3 exactly.
      fact(
        "f2", "Her father kept the light.", "My father kept this light for forty years.",
        Self.letter, "1"),
      // Right, but not in the fixture: unmatched.
      fact("f3", "Wren wears an oilskin coat.", "oilskin coat", Self.lamp, "1"),
      // Right quote, wrong scene: matches nothing.
      fact("f4", "Wren counts.", "I count.", Self.letter, "1"),
    ]
    let scores = EvalScoring.score(
      run(facts, summary: "Wren, a young woman, counts."), against: wren,
      verifier: QuoteVerifier(corpus: corpus))
    #expect(scores.precision == 0.5)
    #expect(scores.recall == 2.0 / 3.0)
    #expect(scores.unmatchedFactIDs == ["f3", "f4"])
    #expect(scores.missedGoldFactIDs == ["g1"])
    #expect(scores.hallucinations == ["m1"])
    #expect(scores.invalidGoldFactIDs.isEmpty)
  }

  @Test("An acceptable fact counts toward precision, not recall")
  func acceptableFacts() async throws {
    let corpus = try await corpus()
    let wren = try #require(try GoldFixtures.load(from: Self.fixtures).first)
    let accepted = CharacterFixture(
      member: wren.member, facts: wren.facts,
      acceptable: [
        GoldFact(
          id: "a1", statement: "Wren wears an oilskin coat.", quote: "oilskin coat",
          episode: Self.lamp, scene: "1")
      ], summary: wren.summary, forbidden: wren.forbidden)
    let scores = EvalScoring.score(
      run([fact("f1", "Wren wears oilskin.", "oilskin coat", Self.lamp, "1")], summary: "x"),
      against: accepted, verifier: QuoteVerifier(corpus: corpus))
    #expect(scores.precision == 1)
    #expect(scores.recall == 0)
  }

  @Test("An unfilled fixture leaves the gold metrics unscored")
  func unfilledFixtureIsNotScored() async throws {
    let fixture = CharacterFixture(
      member: "WREN", facts: [], acceptable: [], summary: "TODO", forbidden: [])
    let scores = EvalScoring.score(
      run([fact("f1", "Wren counts.", "I count.", Self.lamp, "1")], summary: "Wren counts."),
      against: fixture, verifier: QuoteVerifier(corpus: try await corpus()))
    #expect(scores.precision == nil && scores.recall == nil && scores.hallucinations == nil)
    #expect(scores.quoteVerificationRate == 1)
    #expect(EvalThresholds.failures(scores).isEmpty)
  }

  @Test("Threshold failures name the character, the metric and the bar")
  func thresholdFailures() async throws {
    let wren = try #require(try GoldFixtures.load(from: Self.fixtures).first)
    let scores = EvalScoring.score(
      run([fact("f1", "Wren is in her twenties.", "oilskin coat", Self.lamp, "1")], summary: "x"),
      against: wren, verifier: QuoteVerifier(corpus: try await corpus()))
    let failures = EvalThresholds.failures(scores)
    #expect(failures.contains("WREN: made must-not-say claims m1"))
    #expect(failures.contains("WREN: precision 0.00 is below 0.30"))
    #expect(failures.contains("WREN: recall 0.00 is below 0.20"))
  }
}
