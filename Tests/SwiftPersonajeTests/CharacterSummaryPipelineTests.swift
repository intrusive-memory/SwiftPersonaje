import Foundation
import Testing

@testable import SwiftPersonaje

@Suite("Summary pipeline: split, extract, verify, summarize, check (stubbed model)")
struct CharacterSummaryPipelineTests {

  static let lamp = SummarySynthetic.lamp
  static let letter = SummarySynthetic.letter
  static let roomy = ChunkBudget(contextSize: 400, reservedForOutput: 100, overhead: 50)

  struct StubFailure: Error, CustomStringConvertible {
    var description: String { "stub failure" }
  }

  /// Answers by scene. Cites a scene that doesn't exist, which the pipeline
  /// must overwrite with the chunk's.
  struct StubExtractor: CharacterFactExtracting {
    func facts(about member: String, in chunk: SceneChunk) async throws -> [CharacterFact] {
      let bogus = SceneCitation(episode: "bogus.fountain", scene: "99")
      switch (chunk.citation.episode, chunk.citation.scene) {
      case (SummarySynthetic.lamp, "1"):
        return [
          CharacterFact(id: "x", statement: "Wren counts.", quote: "I count.", citation: bogus),
          CharacterFact(
            id: "x", statement: "Wren imagines.", quote: "I imagine everything.", citation: bogus),
        ]
      case (SummarySynthetic.lamp, "3"):
        throw StubFailure()
      default:
        return [
          CharacterFact(
            id: "x", statement: "Wren's father kept the light for forty years.",
            quote: "My father kept this light for forty years.", citation: bogus)
        ]
      }
    }
  }

  /// Writes one sentence per fact, citing it, plus one sentence citing
  /// nothing real.
  struct StubSummarizer: CharacterSummarizing {
    func summary(of member: String, from facts: [CharacterFact]) async throws -> CharacterSummary {
      CharacterSummary(
        member: member,
        sentences: facts.map { SummarySentence(text: $0.statement, factIDs: [$0.id]) }
          + [SummarySentence(text: "Wren sails to France every summer.", factIDs: ["f1"])])
    }
  }

  func run(_ member: String) async throws -> CharacterSummaryRun {
    let corpus = try await SummarySynthetic.corpus()
    let pipeline = CharacterSummaryPipeline(
      corpus: corpus, chunker: SceneChunker(budget: Self.roomy, counter: WordCounter()),
      extractor: StubExtractor(), summarizer: StubSummarizer())
    return try await pipeline.run(for: member)
  }

  @Test("Chunks cover only the member's scenes")
  func chunksCoverMembersScenes() async throws {
    let run = try await run("WREN")
    #expect(
      run.chunks.map(\.citation) == [
        SummarySynthetic.citation(Self.lamp, "1"), SummarySynthetic.citation(Self.lamp, "3"),
        SummarySynthetic.citation(Self.letter, "1"),
      ])
  }

  @Test("Facts get run-wide IDs and their chunk's citation, whatever the extractor said")
  func idsAndCitationsComeFromThePipeline() async throws {
    let run = try await run("WREN")
    #expect(run.extractedFacts.map(\.id) == ["f1", "f2", "f3"])
    #expect(
      run.extractedFacts.map(\.citation) == [
        SummarySynthetic.citation(Self.lamp, "1"), SummarySynthetic.citation(Self.lamp, "1"),
        SummarySynthetic.citation(Self.letter, "1"),
      ])
  }

  @Test("Facts whose quotes don't verify are dropped before summarizing")
  func unverifiedFactsAreDropped() async throws {
    let run = try await run("WREN")
    #expect(run.verifiedFacts.map(\.id) == ["f1", "f3"])
    #expect(run.droppedFacts.map(\.fact.id) == ["f2"])
    #expect(run.quoteVerificationRate == 2.0 / 3.0)
    let summary = try #require(run.summary)
    #expect(summary.sentences.flatMap(\.factIDs).allSatisfy { ["f1", "f3"].contains($0) })
  }

  @Test("A chunk the extractor fails on is recorded and the run goes on")
  func chunkFailureIsRecorded() async throws {
    let run = try await run("WREN")
    #expect(
      run.chunkFailures == [
        ChunkFailure(
          citation: SummarySynthetic.citation(Self.lamp, "3"), part: 1, message: "stub failure")
      ])
  }

  @Test("The summary is checked: an unsupported sentence is flagged")
  func summaryIsChecked() async throws {
    let run = try await run("WREN")
    let report = try #require(run.traceability)
    #expect(report.unsupported.map(\.sentence) == ["Wren sails to France every summer."])
  }

  @Test("With no verified facts, nothing is summarized")
  func noFactsNoSummary() async throws {
    let run = try await run("MAGGIE")  // only lamp scene 3, where the stub throws
    #expect(run.verifiedFacts.isEmpty)
    #expect(run.summary == nil && run.traceability == nil)
    #expect(run.quoteVerificationRate == nil)
  }

  @Test("A run round-trips through JSON, for the evaluation report")
  func runIsCodable() async throws {
    let run = try await run("WREN")
    let data = try JSONEncoder().encode(run)
    #expect(try JSONDecoder().decode(CharacterSummaryRun.self, from: data) == run)
  }
}
