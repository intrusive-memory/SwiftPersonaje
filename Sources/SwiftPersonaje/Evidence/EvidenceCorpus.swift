import Foundation
import SwiftCompartido
import SwiftData

/// A project's episodes, parsed once, ready to answer evidence questions about
/// any cast member (VE-1, VE-5, VE-8).
///
/// Each episode is parsed by SwiftCompartido into its own in-memory store
/// (rule 4: screenplays are read through SwiftCompartido). The episode's text
/// is kept beside it, for two things only:
///
/// - **Sources.** Every element SwiftCompartido returns is placed on its line
///   in the file, so each item carries its line and its SN-1 scene number,
///   looked up through ``SceneNumbering``.
/// - **The scene rule.** A scene starts only at a slugline. SwiftCompartido
///   treats a forced `.` line as a scene heading, which would end a context
///   window there; here a forced line is a block inside the scene before it.
///
/// Nothing here writes a file.
public struct EvidenceCorpus: Sendable {

  /// One parsed episode.
  struct Episode: Sendable {
    /// The episode file's name.
    let name: String
    /// The SwiftCompartido store holding this episode only.
    let store: DocumentModelActor
    /// The episode's headings with SN-1 numbers.
    let headings: [SceneHeading]
    /// The episode's lines, split as ``SceneNumbering`` splits them.
    let lines: [String]
    /// The 0-based line of every element, by `(chapterIndex, orderIndex)`.
    let elementLines: [ElementKey: Int]
    /// The episode's blocks under the scene rule, in script order.
    let blocks: [Block]
    /// The block holding each element, by `(chapterIndex, orderIndex)`.
    let blockOfElement: [ElementKey: Int]
  }

  /// An element's position in SwiftCompartido's store.
  struct ElementKey: Sendable, Hashable {
    let chapter: Int
    let order: Int
  }

  /// A block under the scene rule: one dialogue block, or one body element
  /// (a forced `.` line included).
  struct Block: Sendable, Equatable {
    /// Index into ``Episode/headings``, or `-1` before the first heading.
    var scene: Int
    /// 0-based line of the block's first element.
    var line: Int
    var speaker: String?
    var cue: String?
    var texts: [String]
    var isDialogue: Bool
    /// `true` for an action paragraph (SwiftCompartido's `.action`), the
    /// only blocks VE-2 to VE-4 read.
    var isAction = false

    var text: String { texts.joined(separator: "\n") }
  }

  let episodes: [Episode]

  /// The episode files' names, in load order.
  public var episodeNames: [String] { episodes.map(\.name) }

  // MARK: - Loading

  /// Parses `screenplays`, in order, each into its own SwiftCompartido store.
  ///
  /// - Throws: ``CastDiscoveryError/unreadableScreenplay(path:reason:)`` for
  ///   the first file that can't be read or parsed.
  public static func load(screenplays: [URL]) async throws -> EvidenceCorpus {
    var episodes: [Episode] = []
    for url in screenplays {
      do {
        let text = try String(contentsOf: url, encoding: .utf8)
        let store = DocumentModelActor(modelContainer: try CastDiscovery.makeContainer())
        let id = try await store.parseAndSaveDocument(from: url, parseGlosa: false)
        let elements = try await store.getElements(for: id)
        episodes.append(episode(named: url.lastPathComponent, text: text, store: store, elements: elements))
      } catch {
        throw CastDiscoveryError.unreadableScreenplay(path: url.path, reason: String(describing: error))
      }
    }
    return EvidenceCorpus(episodes: episodes)
  }

  static func episode(
    named name: String, text: String, store: DocumentModelActor,
    elements: [DocumentModelActor.ElementInfo]
  ) -> Episode {
    let lines = splitLines(text)
    let headings = SceneNumbering.numberedHeadings(in: text)
    let located = locate(elements.map(\.elementText), in: lines)

    var elementLines: [ElementKey: Int] = [:]
    for (element, line) in zip(elements, located) {
      elementLines[ElementKey(chapter: element.chapterIndex, order: element.orderIndex)] = line
    }
    let (blocks, blockOfElement) = makeBlocks(
      elements: elements, located: located, lines: lines, headings: headings)
    return Episode(
      name: name, store: store, headings: headings, lines: lines,
      elementLines: elementLines, blocks: blocks, blockOfElement: blockOfElement)
  }

  // MARK: - Evidence

  /// The dialogue, introductions, group statements and context windows of
  /// `member` across every episode.
  ///
  /// ``CharacterEvidence/items`` holds every kind, ordered by episode and
  /// line; see ``actionItems(for:)`` for how action paragraphs are read.
  ///
  /// - Parameters:
  ///   - member: The member's `character` (or any cue of theirs; it is
  ///     cleaned as SwiftCompartido cleans cues).
  ///   - neighbours: Blocks on each side of a line in a context window.
  ///     Default 3 (VE-5).
  /// - Throws: SwiftCompartido's `DocumentModelActorError` from its line
  ///   window query.
  public func evidence(for member: String, neighbours: Int = 3) async throws -> CharacterEvidence {
    var items: [EvidenceItem] = []
    var windows: [EvidenceWindow] = []
    for episode in episodes {
      // SwiftCompartido finds the member's lines (CP-P5). Its windows stop at
      // a forced `.` line, so only their line blocks are used here; the
      // windows are re-cut below under the scene rule.
      let compartidoWindows = try await episode.store.fetchLineWindows(
        for: member, neighbours: neighbours)
      var lineBlocks = Set<Int>()
      for window in compartidoWindows {
        for block in window.blocks where block.isCharacterLine {
          guard let first = block.elements.first else { continue }
          let key = ElementKey(chapter: first.chapterIndex, order: first.orderIndex)
          if let index = episode.blockOfElement[key] { lineBlocks.insert(index) }
          items.append(dialogueItem(from: block, in: episode))
        }
      }
      windows += Self.windows(around: lineBlocks, in: episode, radius: neighbours)
    }
    items += actionItems(for: member)
    items.sort { (order($0.episode), $0.line) < (order($1.episode), $1.line) }
    return CharacterEvidence(member: member, items: items, windows: windows)
  }

  // MARK: - Action evidence (VE-2, VE-3, VE-4)

  /// Every speaker in the corpus, cleaned as SwiftCompartido cleans cues.
  var speakers: Set<String> {
    Set(episodes.flatMap { $0.blocks.compactMap { $0.isDialogue ? $0.speaker : nil } })
  }

  /// The introduction and group-statement items of `member`, in corpus
  /// order. Only action paragraphs are read.
  ///
  /// - A paragraph *names* a character when one of its capitalised names
  ///   holds the character's cue as whole words (VE-3, ``CapitalisedNames``).
  ///   The characters are every speaker in the corpus, plus `member`.
  /// - **Introduction** (VE-2): the first paragraph in the corpus that names
  ///   `member`, and every later one that names them and matches an age,
  ///   ethnicity, build or voice pattern (``IntroductionPatterns``).
  /// - **Group statement** (VE-4): a later paragraph naming `member` and at
  ///   least one other character, without a description; or a paragraph that
  ///   names no character, matches a group pattern (`They each…`) and sits
  ///   in a scene (slugline to slugline, the scene rule) where `member` has
  ///   a dialogue block.
  func actionItems(for member: String) -> [EvidenceItem] {
    let memberName = EvidenceCue.speaker(of: member)
    let memberWords = CapitalisedNames.words(ofCue: memberName)
    let characterWords = (speakers.union([memberName])).map { CapitalisedNames.words(ofCue: $0) }
    var introduced = false
    var items: [EvidenceItem] = []

    for episode in episodes {
      var speakersByScene: [Int: Set<String>] = [:]
      for block in episode.blocks where block.isDialogue {
        if let speaker = block.speaker { speakersByScene[block.scene, default: []].insert(speaker) }
      }

      for block in episode.blocks where block.isAction {
        let text = Self.writtenText(of: block, in: episode)
        let names = CapitalisedNames.names(in: text)
        let namedCount = names.filter { name in
          characterWords.contains { CapitalisedNames.name(name, matches: $0) }
        }.count
        let memberMatch = names.first { CapitalisedNames.name($0, matches: memberWords) }

        let kind: EvidenceItem.Kind
        if memberMatch != nil {
          if !introduced {
            introduced = true
            kind = .introduction
          } else if IntroductionPatterns.describesCharacter(text) {
            kind = .introduction
          } else if namedCount >= 2 {
            kind = .groupStatement
          } else {
            continue
          }
        } else if namedCount == 0, IntroductionPatterns.refersToGroup(text),
          speakersByScene[block.scene]?.contains(memberName) == true
        {
          kind = .groupStatement
        } else {
          continue
        }

        items.append(
          EvidenceItem(
            kind: kind,
            episode: episode.name,
            line: block.line + 1,
            sceneNumber: SceneNumbering.numberForScene(atLine: block.line, in: episode.headings),
            text: text,
            matchedName: memberMatch?.written))
      }
    }
    return items
  }

  /// An action paragraph's exact text in the file: its lines from the
  /// block's line to the next blank line, trimmed, a forced-action `!`
  /// removed. Falls back to SwiftCompartido's text when the file's line
  /// doesn't hold it (an element that couldn't be placed).
  static func writtenText(of block: Block, in episode: Episode) -> String {
    var lines: [String] = []
    var index = block.line
    while index < episode.lines.count {
      let line = episode.lines[index].trimmingCharacters(in: .whitespaces)
      if line.isEmpty { break }
      lines.append(line)
      index += 1
    }
    if var first = lines.first, first.hasPrefix("!") {
      first.removeFirst()
      lines[0] = first
    }
    let firstPart =
      block.text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    guard let head = lines.first, !firstPart.isEmpty, head.contains(firstPart) else {
      return block.text
    }
    return lines.joined(separator: "\n")
  }

  private func order(_ episode: String) -> Int {
    episodes.firstIndex(where: { $0.name == episode }) ?? episodes.count
  }

  /// A dialogue item from one of SwiftCompartido's line blocks.
  private func dialogueItem(from block: ScriptBlockInfo, in episode: Episode) -> EvidenceItem {
    let cueElement = block.elements.first { $0.elementType == .character }
    let anchor = cueElement ?? block.elements.first
    let line =
      anchor.flatMap {
        episode.elementLines[ElementKey(chapter: $0.chapterIndex, order: $0.orderIndex)]
      } ?? 0
    return EvidenceItem(
      kind: .dialogue,
      episode: episode.name,
      line: line + 1,
      sceneNumber: SceneNumbering.numberForScene(atLine: line, in: episode.headings),
      text: block.text,
      cue: cueElement?.text,
      extensions: cueElement.map { EvidenceCue.extensions(of: $0.text) } ?? [],
      parentheticals: block.elements.filter { $0.elementType == .parenthetical }.map(\.text)
    )
  }

  // MARK: - Windows (VE-5)

  /// The ±`radius` windows around `lineBlocks`, clipped to each scene under
  /// the scene rule, with windows that share a block merged. Windows that
  /// only touch stay separate (as in SwiftCompartido's CP-P5).
  static func windows(around lineBlocks: Set<Int>, in episode: Episode, radius: Int)
    -> [EvidenceWindow]
  {
    var result: [EvidenceWindow] = []
    var start = 0
    while start < episode.blocks.count {
      let scene = episode.blocks[start].scene
      var end = start
      while end < episode.blocks.count && episode.blocks[end].scene == scene { end += 1 }

      let centres = (start..<end).filter { lineBlocks.contains($0) }
      for range in mergedRanges(around: centres, lower: start, upper: end - 1, radius: radius) {
        let blocks = range.map { index in
          let block = episode.blocks[index]
          return EvidenceBlock(
            line: block.line + 1, speaker: block.speaker, cue: block.cue, text: block.text,
            isMemberLine: lineBlocks.contains(index))
        }
        let heading = scene >= 0 ? episode.headings[scene] : nil
        result.append(
          EvidenceWindow(
            episode: episode.name,
            sceneNumber: heading?.number,
            heading: heading.map { trimTrailing(episode.lines[$0.lineIndex]) },
            blocks: blocks))
      }
      start = end
    }
    return result
  }

  /// Windows `max(lower, c - radius) ... min(upper, c + radius)` around each
  /// centre, sorted, merged where they share at least one index.
  static func mergedRanges(around centres: [Int], lower: Int, upper: Int, radius: Int)
    -> [ClosedRange<Int>]
  {
    guard lower <= upper, radius >= 0 else { return [] }
    var merged: [ClosedRange<Int>] = []
    for centre in centres.sorted() where centre >= lower && centre <= upper {
      let window = max(lower, centre - radius)...min(upper, centre + radius)
      if let last = merged.last, window.lowerBound <= last.upperBound {
        merged[merged.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
      } else {
        merged.append(window)
      }
    }
    return merged
  }

  // MARK: - Blocks under the scene rule

  /// Groups an episode's elements into blocks, the way SwiftCompartido's
  /// CP-P5 does, except that scenes are cut only at SN-1 headings:
  ///
  /// - An element on a heading's line bounds the scene and is not a block.
  /// - A forced `.` line (a SwiftCompartido scene heading that is not a
  ///   slugline) is a block of its own, inside the scene before it.
  /// - A cue opens a dialogue block; parentheticals and dialogue join it.
  /// - Comments, boneyard, synopses, section headings and page breaks are
  ///   skipped and don't close a dialogue block.
  /// - Every other element is a block of its own.
  static func makeBlocks(
    elements: [DocumentModelActor.ElementInfo], located: [Int], lines: [String],
    headings: [SceneHeading]
  ) -> (blocks: [Block], blockOfElement: [ElementKey: Int]) {
    let headingLines = Set(headings.map(\.lineIndex))
    var blocks: [Block] = []
    var blockOfElement: [ElementKey: Int] = [:]
    var open: Block?
    var openKeys: [ElementKey] = []
    var lastSpeaker: String?

    func close() {
      guard let block = open else { return }
      for key in openKeys { blockOfElement[key] = blocks.count }
      blocks.append(block)
      open = nil
      openKeys = []
    }

    func sceneIndex(atLine line: Int) -> Int {
      headings.lastIndex(where: { $0.lineIndex <= line }) ?? -1
    }

    for (element, line) in zip(elements, located) {
      let key = ElementKey(chapter: element.chapterIndex, order: element.orderIndex)
      let scene = sceneIndex(atLine: line)
      if let current = open, current.scene != scene { close() }

      switch element.elementType {
      case .sceneHeading where headingLines.contains(line):
        close()

      case .comment, .boneyard, .synopsis, .sectionHeading, .pageBreak:
        continue

      case .character:
        close()
        let speaker = EvidenceCue.speaker(of: element.elementText)
        lastSpeaker = speaker.isEmpty ? nil : speaker
        open = Block(
          scene: scene, line: line, speaker: lastSpeaker, cue: element.elementText, texts: [],
          isDialogue: true)
        openKeys = [key]

      case .dialogue, .parenthetical:
        if open == nil {
          open = Block(
            scene: scene, line: line, speaker: lastSpeaker, cue: nil, texts: [], isDialogue: true)
        }
        open?.texts.append(element.elementText)
        openKeys.append(key)

      case .sceneHeading:
        // A forced line: text as written, leading `.` included.
        close()
        let written = line < lines.count ? lines[line].trimmingCharacters(in: .whitespaces) : ""
        let text = written.isEmpty ? element.elementText : written
        blockOfElement[key] = blocks.count
        blocks.append(
          Block(scene: scene, line: line, speaker: nil, cue: nil, texts: [text], isDialogue: false))

      default:
        close()
        blockOfElement[key] = blocks.count
        blocks.append(
          Block(
            scene: scene, line: line, speaker: nil, cue: nil, texts: [element.elementText],
            isDialogue: false, isAction: element.elementType == .action))
      }
    }
    close()
    return (blocks, blockOfElement)
  }

  // MARK: - Placing elements on lines

  /// The 0-based line of each element, found by walking the file once.
  ///
  /// Each element's text lines (trimmed, blank ones dropped) are looked for
  /// in order from just after the previous element, as substrings of the
  /// trimmed file lines; Fountain markup the parser strips (`.`, `>`, `#n#`,
  /// `[[ ]]`, `/* */`) only ever surrounds the text. An element that can't be
  /// found takes the previous element's line. A title page (a first block of
  /// `Key:` lines) is skipped, as the parser skips it.
  static func locate(_ texts: [String], in lines: [String]) -> [Int] {
    let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }

    func find(_ part: String, from start: Int) -> Int? {
      var index = start
      while index < trimmed.count {
        if trimmed[index].contains(part) { return index }
        index += 1
      }
      return nil
    }

    var cursor = titlePageEnd(trimmed)
    var previous = max(0, cursor - 1)
    var result: [Int] = []
    result.reserveCapacity(texts.count)
    for text in texts {
      let parts = text.split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      guard let first = parts.first, let found = find(first, from: cursor) else {
        result.append(previous)
        continue
      }
      result.append(found)
      previous = found
      cursor = found + 1
      for part in parts.dropFirst() {
        if let next = find(part, from: cursor) { cursor = next + 1 }
      }
    }
    return result
  }

  /// The first line after a title page, or 0 when the file has none.
  static func titlePageEnd(_ trimmed: [String]) -> Int {
    guard let firstLine = trimmed.firstIndex(where: { !$0.isEmpty }) else { return 0 }
    let line = trimmed[firstLine]
    guard let colon = line.firstIndex(of: ":"), colon > line.startIndex else { return 0 }
    var index = firstLine
    while index < trimmed.count && !trimmed[index].isEmpty { index += 1 }
    return index
  }

  /// Lines split at `\n`, a trailing `\r` dropped: the same lines, and the
  /// same 0-based indexes, as ``SceneNumbering``.
  static func splitLines(_ text: String) -> [String] {
    // Split on scalars: as Characters, "\r\n" is one grapheme and would not
    // split at "\n".
    text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      var scalars = String.UnicodeScalarView(line)
      if scalars.last == "\r" { scalars.removeLast() }
      return String(scalars)
    }
  }

  private static func trimTrailing(_ line: String) -> String {
    var result = Substring(line)
    while let last = result.last, last.isWhitespace { result.removeLast() }
    return String(result)
  }
}
