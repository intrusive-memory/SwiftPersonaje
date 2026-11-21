import Foundation

/// A fact dropped because its quote didn't verify.
public struct DroppedFact: Sendable, Equatable, Codable {
  public let fact: CharacterFact
  public let verdict: QuoteVerdict
}

/// A chunk the extractor failed on. The run goes on without it.
public struct ChunkFailure: Sendable, Equatable, Codable {
  public let citation: SceneCitation
  public let part: Int
  public let message: String
}

/// Everything one pipeline run produced for one member, kept for scoring.
public struct CharacterSummaryRun: Sendable, Equatable, Codable {
  public let member: String
  public let chunks: [SceneChunk]
  /// Every fact the extractor returned, IDs and citations set by the
  /// pipeline.
  public let extractedFacts: [CharacterFact]
  public let verifiedFacts: [CharacterFact]
  public let droppedFacts: [DroppedFact]
  public let chunkFailures: [ChunkFailure]
  /// `nil` when no fact verified: nothing is summarized from nothing.
  public let summary: CharacterSummary?
  public let traceability: TraceabilityReport?
  /// The summarizer's error, when it threw: the run keeps its facts.
  public let summaryFailure: String?

  public init(
    member: String, chunks: [SceneChunk], extractedFacts: [CharacterFact],
    verifiedFacts: [CharacterFact], droppedFacts: [DroppedFact], chunkFailures: [ChunkFailure],
    summary: CharacterSummary?, traceability: TraceabilityReport?, summaryFailure: String? = nil
  ) {
    self.member = member
    self.chunks = chunks
    self.extractedFacts = extractedFacts
    self.verifiedFacts = verifiedFacts
    self.droppedFacts = droppedFacts
    self.chunkFailures = chunkFailures
    self.summary = summary
    self.traceability = traceability
    self.summaryFailure = summaryFailure
  }

  /// Verified facts over extracted facts; `nil` when none were extracted.
  public var quoteVerificationRate: Double? {
    extractedFacts.isEmpty
      ? nil : Double(verifiedFacts.count) / Double(extractedFacts.count)
  }
}

/// The summary pipeline: split, extract, verify, summarize, check.
///
/// 1. **Split.** ``EvidenceCorpus/scenes(featuring:)``, cut by the
///    ``SceneChunker``.
/// 2. **Extract.** The extractor runs once per chunk. Each fact it returns
///    is given the chunk's citation and a run-wide ID (`f1`, `f2`, …),
///    whatever it said. A fact repeating an earlier one (same scene, same
///    statement and quote after normalization, case aside) is dropped. A
///    chunk that throws is recorded and skipped.
/// 3. **Verify.** ``QuoteVerifier`` checks every quote; facts that fail are
///    dropped.
/// 4. **Summarize** from the verified facts only, then
///    ``SummaryTraceability`` checks every sentence.
///
/// No step trusts the model: the pipeline is model-free, and the model sits
/// behind the two protocols.
public struct CharacterSummaryPipeline: Sendable {
  public let corpus: EvidenceCorpus
  public let chunker: SceneChunker
  public let extractor: any CharacterFactExtracting
  public let summarizer: any CharacterSummarizing

  public init(
    corpus: EvidenceCorpus, chunker: SceneChunker, extractor: any CharacterFactExtracting,
    summarizer: any CharacterSummarizing
  ) {
    self.corpus = corpus
    self.chunker = chunker
    self.extractor = extractor
    self.summarizer = summarizer
  }

  /// - Throws: ``SceneChunkerError`` when the scenes can't be chunked.
  ///   Extractor errors are recorded per chunk, and a summarizer error in
  ///   ``CharacterSummaryRun/summaryFailure``.
  public func run(for member: String) async throws -> CharacterSummaryRun {
    let chunks = try await chunker.chunks(of: corpus.scenes(featuring: member))

    var extracted: [CharacterFact] = []
    var seen = Set<DuplicateKey>()
    var failures: [ChunkFailure] = []
    for chunk in chunks {
      do {
        for fact in try await extractor.facts(about: member, in: chunk) {
          let key = DuplicateKey(fact, citation: chunk.citation)
          guard seen.insert(key).inserted else { continue }
          extracted.append(
            CharacterFact(
              id: "f\(extracted.count + 1)", statement: fact.statement, quote: fact.quote,
              citation: chunk.citation))
        }
      } catch {
        failures.append(
          ChunkFailure(
            citation: chunk.citation, part: chunk.part, message: String(describing: error)))
      }
    }

    let (verified, dropped) = QuoteVerifier(corpus: corpus).partition(extracted)
    var summary: CharacterSummary?
    var traceability: TraceabilityReport?
    var summaryFailure: String?
    if !verified.isEmpty {
      do {
        let written = try await summarizer.summary(of: member, from: verified)
        summary = written
        traceability = SummaryTraceability.check(written, facts: verified)
      } catch {
        summaryFailure = String(describing: error)
      }
    }

    return CharacterSummaryRun(
      member: member, chunks: chunks, extractedFacts: extracted, verifiedFacts: verified,
      droppedFacts: dropped.map { DroppedFact(fact: $0.fact, verdict: $0.verdict) },
      chunkFailures: failures, summary: summary, traceability: traceability,
      summaryFailure: summaryFailure)
  }
}

/// What makes two extracted facts the same fact.
struct DuplicateKey: Hashable {
  let citation: SceneCitation
  let statement: String
  let quote: String

  init(_ fact: CharacterFact, citation: SceneCitation) {
    self.citation = citation
    self.statement = QuoteText.normalize(fact.statement).lowercased()
    self.quote = QuoteText.normalize(QuoteText.unwrap(fact.quote)).lowercased()
  }
}
