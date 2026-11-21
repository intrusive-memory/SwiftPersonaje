import Foundation
import Testing

@testable import SwiftPersonaje

@Suite("Summary traceability: every summary sentence has a supporting fact")
struct SummaryTraceabilityTests {

  static let scene = SceneCitation(episode: SummarySynthetic.lamp, scene: "1")

  static let facts = [
    CharacterFact(
      id: "f1", statement: "Wren notices the lamp has been dark for three nights.",
      quote: "The lamp's been dark three nights running", citation: scene),
    CharacterFact(
      id: "f2", statement: "Wren counts things rather than imagining them.",
      quote: "I don't imagine. I count.", citation: scene),
  ]

  @Test("A sentence citing a fact that shares its content words is supported")
  func citedFactSupports() {
    let summary = CharacterSummary(
      member: "WREN",
      sentences: [
        SummarySentence(text: "Wren noticed the lamp went dark.", factIDs: ["f1"]),
        SummarySentence(text: "She counts; she doesn't imagine.", factIDs: ["f2"]),
      ])
    let report = SummaryTraceability.check(summary, facts: Self.facts)
    #expect(report.isFullyTraceable)
    #expect(report.sentences.map(\.supportingFactIDs) == [["f1"], ["f2"]])
    #expect(report.rate == 1)
  }

  @Test("A sentence about something no fact mentions is flagged")
  func unsupportedSentenceIsFlagged() {
    let summary = CharacterSummary(
      member: "WREN",
      sentences: [
        SummarySentence(text: "Wren noticed the lamp went dark.", factIDs: ["f1"]),
        SummarySentence(text: "Wren was once a sailor in the navy.", factIDs: ["f1"]),
      ])
    let report = SummaryTraceability.check(summary, facts: Self.facts)
    #expect(!report.isFullyTraceable)
    #expect(report.unsupported.map(\.sentence) == ["Wren was once a sailor in the navy."])
    #expect(report.rate == 0.5)
  }

  @Test("A sentence is checked only against the facts it cites")
  func onlyCitedFactsCount() {
    let summary = CharacterSummary(
      member: "WREN",
      sentences: [SummarySentence(text: "Wren counts and never imagines.", factIDs: ["f1"])])
    #expect(!SummaryTraceability.check(summary, facts: Self.facts).isFullyTraceable)
  }

  @Test("A cited ID that isn't among the facts supports nothing and is reported")
  func unknownFactID() throws {
    let summary = CharacterSummary(
      member: "WREN",
      sentences: [SummarySentence(text: "Wren noticed the lamp went dark.", factIDs: ["f9"])])
    let trace = try #require(SummaryTraceability.check(summary, facts: Self.facts).sentences.first)
    #expect(!trace.isSupported)
    #expect(trace.unknownFactIDs == ["f9"])
  }

  @Test("The member's own name is not evidence of support")
  func nameAloneDoesNotSupport() {
    let summary = CharacterSummary(
      member: "WREN",
      sentences: [SummarySentence(text: "Wren is Wren's oldest friend.", factIDs: ["f1", "f2"])])
    #expect(!SummaryTraceability.check(summary, facts: Self.facts).isFullyTraceable)
  }

  @Test("Uncited prose is split into sentences, each checked against every fact")
  func uncitedProse() {
    let report = SummaryTraceability.check(
      text: "Wren counts things. She saw the lamp go dark for three nights. She owns a boat.",
      member: "WREN", facts: Self.facts)
    #expect(report.sentences.count == 3)
    #expect(report.sentences.map(\.isSupported) == [true, true, false])
    #expect(report.sentences[1].supportingFactIDs == ["f1"])
  }

  @Test("Plural and verb endings match their stems")
  func stems() {
    #expect(SummaryTraceability.words(in: "counts counted counting") == ["count", "count", "count"])
    #expect(SummaryTraceability.words(in: "the and was") == [])
  }
}
