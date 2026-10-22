import Foundation

/// Synthetic screenplays and project scaffolding. Nothing here comes from a
/// real production (REQUIREMENTS §9: this repository is public).
enum Synthetic {

  static let episodeOne = """
    Title: Episode One

    INT. KITCHEN - DAY

    BOB
    Hello there.

    ALICE (V.O.)
    Hi, Bob.

    COP #1
    Freeze!

    EXT. STREET - NIGHT

    BOB (CONT'D)
    Still here.
    """

  static let episodeTwo = """
    Title: Episode Two

    INT. BAR - NIGHT

    BARTENDER
    What'll it be?

    BOB
    Whiskey.

    ALICE
    Same.

    ZED
    Last call.
    """

  static let episodeThree = """
    Title: Episode Three

    EXT. PIER - DAWN

    NARRATOR (V.O.)
    It ended where it began.

    ALICE
    Did it?

    An empty boat drifts past. No one speaks.
    """

  static let episodes: [(name: String, text: String)] = [
    ("01-one.fountain", episodeOne),
    ("02-two.fountain", episodeTwo),
    ("03-three.fountain", episodeThree),
  ]

  /// A fresh, empty directory under the temporary directory.
  static func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftPersonajeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
  }

  /// A project directory with PROJECT.md and the three episodes under
  /// `episodes/`. `frontMatterExtra` is appended to PROJECT.md's front matter.
  static func makeProject(frontMatterExtra: String = "") throws -> URL {
    let dir = try makeDirectory()
    let episodes = dir.appendingPathComponent("episodes", isDirectory: true)
    try FileManager.default.createDirectory(at: episodes, withIntermediateDirectories: true)
    for episode in Self.episodes {
      try write(episode.text, to: episodes.appendingPathComponent(episode.name))
    }
    try write(
      """
      ---
      type: project
      title: Synthetic Series
      author: Test Author
      created: 2026-01-01T00:00:00Z
      \(frontMatterExtra)
      ---

      A made-up series for tests.

      """,
      to: dir.appendingPathComponent("PROJECT.md"))
    return dir
  }

  static func episodeURLs(in project: URL, _ names: [String]) -> [URL] {
    names.map {
      project.appendingPathComponent("episodes", isDirectory: true).appendingPathComponent($0)
    }
  }

  static func write(_ text: String, to url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  static func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }
}
