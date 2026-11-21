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

@Suite("Baseline fixes from the first model comparison (no model)")
struct BaselineComparisonFixTests {

  @Test("A quote repeated in one response is kept once, with its first statement")
  func repeatedQuotesAreKeptOnce() throws {
    // As Qwen3.5-9B looped under greedy decoding.
    let looped = Array(repeating: "\"MITCH... ordering one for BILLY.\" -> Mitch orders for Billy.", count: 5)
      .joined(separator: "\n")
    let facts = try BaselineFormat.facts(
      in: looped + "\n\"I count.\" -> Wren counts.\n\"i count.\" -> Wren counts again.")
    #expect(facts.map(\.quote) == ["ordering one for BILLY.", "I count."])
    #expect(facts.map(\.statement) == ["Mitch orders for Billy.", "Wren counts."])
  }

  @Test("A capitalized cue without a colon is dropped, as screenplays print it")
  func cueWithoutColon() throws {
    let facts = try BaselineFormat.facts(
      in: """
        FACT: Mitch orders a drink.
        QUOTE: MITCH (to the bartender) Can I get another gin martini?
        FACT: Mitch remembers a name.
        QUOTE: MITCH Used to be a guy named Mac something.
        FACT: Mitch notices Donnie.
        QUOTE: MITCH notices LITTLE DONNIE WYNANT, standing just outside the room.
        FACT: Mitch speaks off screen.
        QUOTE: AUNT STANLEY (O.S.) Who's there?
        FACT: Wren counts.
        QUOTE: I Count.
        """)
    #expect(
      facts.map(\.quote) == [
        "Can I get another gin martini?",
        "Used to be a guy named Mac something.",
        // An action line keeps its subject: a lowercase word follows.
        "MITCH notices LITTLE DONNIE WYNANT, standing just outside the room.",
        "Who's there?",
        // "I" is never a cue.
        "I Count.",
      ])
  }

  @Test("A quote that is only a cue and an ellipsis is dropped")
  func cueOnlyQuote() throws {
    let facts = try BaselineFormat.facts(
      in: "\"TOBY ...\" -> Toby speaks.\n\"Hi, Toby.\" -> Someone greets Toby.")
    #expect(facts.map(\.quote) == ["Hi, Toby."])
  }

  @Test("A summary keeps at most three sentences and records how many came back")
  func summaryLength() {
    // As Qwen3.5-9B answered: one line, several sentences, no citation.
    let long = BaselineSummarizer.limited(
      member: "MITCH",
      [
        SummarySentence(
          text:
            "Mitch is a photojournalist. He lives in San Francisco. He likes puzzles. He drinks martinis.",
          factIDs: ["f1"])
      ])
    #expect(long.sentences.map(\.text) == [
      "Mitch is a photojournalist.", "He lives in San Francisco.", "He likes puzzles.",
    ])
    #expect(long.sentences.allSatisfy { $0.factIDs == ["f1"] })
    #expect(long.returnedSentenceCount == 4)

    let short = BaselineSummarizer.limited(
      member: "WREN", [SummarySentence(text: "Wren counts.", factIDs: ["f2"])])
    #expect(short.sentences.count == 1)
    #expect(short.returnedSentenceCount == nil)
  }
}
