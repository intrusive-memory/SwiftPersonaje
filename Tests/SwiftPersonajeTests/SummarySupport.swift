import Foundation

@testable import SwiftPersonaje

/// A synthetic two-episode lighthouse series for the summary pipeline's
/// deterministic tests. Invented here; nothing comes from a real production
/// (REQUIREMENTS §9).
///
/// It carries the typographic forms quote verification normalizes: curly
/// apostrophes and quotes, a `--` dash and an `—` dash, dialogue broken over
/// lines, a parenthetical inside a speech, and a speech long enough to split.
enum SummarySynthetic {

  static let lamp = "01-the-lamp.fountain"
  static let letter = "02-the-letter.fountain"

  // Scene 1: WREN and OTTO in the lighthouse. Scene 2: OTTO alone. Scene 3:
  // MAGGIE; WREN is only named in action.
  static let lampText = """
    Title: The Lamp
    Credit: Episode 1

    INT. LIGHTHOUSE - NIGHT

    WREN, 60's, oilskin coat, climbs the spiral stair.

    WREN
    The lamp’s been dark three nights running -- and nobody’s said a word.
    (beat)
    Not one word.

    OTTO
    You’re imagining things—again.

    WREN
    I don't imagine.
    I count.

    EXT. HARBOUR WALL - DAWN

    OTTO walks the wall alone.

    OTTO (V.O.)
    She counts everything. Even me.

    INT. POST OFFICE - DAY

    MAGGIE sorts a stack of letters addressed to WREN.

    MAGGIE
    “Nothing for the lighthouse,” she says. Again.
    """

  // Scene 1: a long WREN speech, for splitting.
  static let letterText = """
    Title: The Letter
    Credit: Episode 2

    INT. LIGHTHOUSE KITCHEN - MORNING

    WREN
    My father kept this light for forty years.
    He never missed a night, not once, not in the war.
    He wrote every ship down in a green ledger.
    I have all of them upstairs in a tea chest.
    Nobody has asked to see them since he died.

    OTTO
    I'd like to see them.
    """

  static func project() throws -> URL {
    let dir = try Synthetic.makeDirectory()
    let episodes = dir.appendingPathComponent("episodes", isDirectory: true)
    try FileManager.default.createDirectory(at: episodes, withIntermediateDirectories: true)
    try Synthetic.write(lampText, to: episodes.appendingPathComponent(lamp))
    try Synthetic.write(letterText, to: episodes.appendingPathComponent(letter))
    return dir
  }

  static func corpus() async throws -> EvidenceCorpus {
    let dir = try project()
    return try await EvidenceCorpus.load(
      screenplays: Synthetic.episodeURLs(in: dir, [lamp, letter]))
  }

  static func citation(_ episode: String, _ scene: String?) -> SceneCitation {
    SceneCitation(episode: episode, scene: scene)
  }
}

/// Counts whitespace-separated words: deterministic, and close enough to a
/// tokenizer for budget arithmetic.
struct WordCounter: TokenCounting {
  func tokenCount(for text: String) async throws -> Int {
    text.split(whereSeparator: \.isWhitespace).count
  }
}
