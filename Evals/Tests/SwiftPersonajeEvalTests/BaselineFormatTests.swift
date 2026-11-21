import Foundation
import PersonajeEvalKit
import SwiftPersonaje
import Testing

/// The baseline's plain-text formats, parsed with no model.
@Suite("Baseline response formats (no model)")
struct BaselineFormatTests {

  @Test("Quote-first lines are parsed: \"quote\" -> fact")
  func arrowLines() throws {
    let facts = try BaselineFormat.facts(
      in: """
        "The lamp’s been dark three nights running" -> Wren notices the lamp is out.
        1. “I don't imagine. I count.” → Wren trusts counting.
        - Wren: "I count." — Wren counts.
        "Nothing for the lighthouse," she says. Again. -> Wren expects post.
        "WREN: My father kept this light for forty years." -> Wren's father kept the light.
        """)
    #expect(
      facts.map(\.quote) == [
        "The lamp’s been dark three nights running", "I don't imagine. I count.", "I count.",
        "\"Nothing for the lighthouse,\" she says. Again.",
        "My father kept this light for forty years.",
      ])
    #expect(
      facts.map(\.statement) == [
        "Wren notices the lamp is out.", "Wren trusts counting.", "Wren counts.", "Wren expects post.",
        "Wren's father kept the light.",
      ])
  }

  @Test("FACT/QUOTE pairs are parsed in order")
  func factPairs() throws {
    let facts = try BaselineFormat.facts(
      in: """
        FACT: Wren notices the lamp has been dark.
        QUOTE: The lamp's been dark three nights running

        FACT: Wren counts things.
        QUOTE: I count.
        """)
    #expect(facts.map(\.statement) == ["Wren notices the lamp has been dark.", "Wren counts things."])
    #expect(facts.map(\.quote) == ["The lamp's been dark three nights running", "I count."])
  }

  @Test("List markers, bold labels, lowercase labels and run-on quotes are tolerated")
  func tolerantParsing() throws {
    let facts = try BaselineFormat.facts(
      in: """
        1. **FACT:** Wren doubts Otto.
           **QUOTE:** I don't imagine.
           I count.
        - fact: Wren climbs the stair.
        - quote: climbs the spiral stair
        """)
    #expect(facts.count == 2)
    #expect(facts[0].quote == "I don't imagine. I count.")
    #expect(facts[1].statement == "Wren climbs the stair.")
  }

  @Test("A FACT with nothing after it is dropped")
  func factWithoutQuote() throws {
    let facts = try BaselineFormat.facts(
      in: "FACT: Wren is tired.\nFACT: Wren counts.\nQUOTE: I count.")
    #expect(facts.map(\.statement) == ["Wren counts."])
  }

  @Test("Without a QUOTE label, the quoted line after the FACT is the quote")
  func unlabeledQuote() throws {
    // As the on-device model answered: the statement repeated, then the quote.
    let facts = try BaselineFormat.facts(
      in: """
        FACT: Wren is expecting letters.

        Wren is expecting letters.

        "Nothing for the lighthouse," she says. Again.
        FACT: Wren's father kept the light.

        Wren: "My father kept this light for forty years."
        FACT: Wren is guarded.
        Nobody has asked to see them since he died.
        """)
    #expect(
      facts.map(\.quote) == [
        "\"Nothing for the lighthouse,\" she says. Again.",
        "\"My father kept this light for forty years.\"",
        "Nobody has asked to see them since he died.",
      ])
  }

  @Test("A speaker prefix is dropped only in front of a quoted line")
  func speakerPrefix() throws {
    let facts = try BaselineFormat.facts(
      in: """
        FACT: The moderator thanks Mitch.
        QUOTE: MODERATOR: "Thank you, Mitch."
        FACT: Mitch keeps a list.
        QUOTE: Note: buy more ink.
        FACT: Wren's father kept the light.
        QUOTE: WREN: My father kept this light for forty years.
        FACT: Otto speaks off screen.
        QUOTE: OTTO (V.O.): She counts everything.
        """)
    #expect(
      facts.map(\.quote) == [
        "\"Thank you, Mitch.\"", "Note: buy more ink.",
        "My father kept this light for forty years.", "She counts everything.",
      ])
  }

  @Test("NONE means no facts; anything else without a pair is a refusal")
  func noneAndRefusal() throws {
    #expect(try BaselineFormat.facts(in: "NONE").isEmpty)
    #expect(try BaselineFormat.facts(in: "None.").isEmpty)
    #expect(throws: BaselineError.unparseable(response: "I can't help with that. ⏎ Sorry.")) {
      try BaselineFormat.facts(in: "I can't help with that.\nSorry.")
    }
  }

  @Test("SENTENCE lines carry their cited IDs, in brackets or parentheses")
  func sentences() throws {
    let sentences = try BaselineFormat.sentences(
      in: """
        SENTENCE: Wren keeps count of everything. [f2, f5]
        SENTENCE: Her father kept the light (f7).
        - SENTENCE: She distrusts Otto [f1 and f3].
        SENTENCE: Nobody listens to her.
        """)
    #expect(
      sentences == [
        SummarySentence(text: "Wren keeps count of everything.", factIDs: ["f2", "f5"]),
        SummarySentence(text: "Her father kept the light.", factIDs: ["f7"]),
        SummarySentence(text: "She distrusts Otto.", factIDs: ["f1", "f3"]),
        SummarySentence(text: "Nobody listens to her.", factIDs: []),
      ])
  }

  @Test("Without SENTENCE labels, every line is a sentence")
  func unlabeledSentences() throws {
    // As the on-device model answered.
    let sentences = try BaselineFormat.sentences(
      in: """
        WREN is the keeper of the lighthouse. (f1)
        WREN is responsible for the lamp, which has been dark for three nights. (f1)
        """)
    #expect(sentences.map(\.factIDs) == [["f1"], ["f1"]])
    #expect(sentences[0].text == "WREN is the keeper of the lighthouse.")
  }

  @Test("An empty summary response is an error")
  func summaryRefusal() {
    #expect(throws: BaselineError.self) { try BaselineFormat.sentences(in: "  \n ") }
  }
}

@Suite("Bruja responses (no model)")
struct BrujaResponseTests {
  @Test("A thinking block is removed, closed or left open at the end")
  func thinkingIsRemoved() {
    #expect(BrujaGenerator.withoutThinking("<think>hmm\nok</think>\nNONE") == "NONE")
    #expect(BrujaGenerator.withoutThinking("\"I count.\" -> Wren counts.<think>more") == "\"I count.\" -> Wren counts.")
    #expect(BrujaGenerator.withoutThinking("NONE") == "NONE")
  }
}
