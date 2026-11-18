import Foundation

/// Capitalised names in action lines, and whole-word matching against a cue
/// (VE-3).
///
/// A *capitalised name* is a run of words written in capitals (no lowercase
/// letter), joined only by spaces, periods or quotation marks:
/// `CONSTABLE HAROLD "HAL" BRISK` is one name; `PIP, NED and TOBY` is three;
/// `WICKHAM & SONS` is two (`WICKHAM`, `SONS`).
///
/// A name matches cue `X` only when it contains `X`'s words, in order and
/// next to each other, as whole words. `CONSTABLE HAROLD "HAL" BRISK` matches
/// `CONSTABLE`; `CONSTABLEWICK` doesn't, and `WICKHAM` doesn't match `WICK`.
/// A possessive `'S` is dropped before comparing (`CONSTABLE'S` is the
/// constable's).
enum CapitalisedNames {

  /// One capitalised name found in a text.
  struct Name: Sendable, Equatable {
    /// The name as written, from its first word to its last.
    let written: String
    /// Its words, normalised for comparison.
    let words: [String]
  }

  /// Every capitalised name in `text`, in order.
  static func names(in text: String) -> [Name] {
    var names: [Name] = []
    var runStart: String.Index?
    var runEnd: String.Index?
    var runWords: [String] = []

    func closeRun() {
      if let start = runStart, let end = runEnd, !runWords.isEmpty {
        names.append(Name(written: String(text[start..<end]), words: runWords))
      }
      runStart = nil
      runEnd = nil
      runWords = []
    }

    var index = text.startIndex
    var separator = ""
    while index < text.endIndex {
      guard isWordCharacter(text[index]) else {
        separator.append(text[index])
        index = text.index(after: index)
        continue
      }
      let start = index
      while index < text.endIndex && isWordCharacter(text[index]) {
        index = text.index(after: index)
      }
      let token = String(text[start..<index])
      if isCapitalised(token) {
        if runStart != nil && !joinsName(separator) { closeRun() }
        if runStart == nil { runStart = start }
        runEnd = index
        runWords.append(normalised(token))
      } else {
        closeRun()
      }
      separator = ""
    }
    closeRun()
    return names
  }

  /// A cue's words, normalised as name words are (`MR. SMITH` → `MR`,
  /// `SMITH`). The cue is cleaned as SwiftCompartido cleans cues first.
  static func words(ofCue cue: String) -> [String] {
    var words: [String] = []
    var current = ""
    for character in EvidenceCue.speaker(of: cue) {
      if isWordCharacter(character) {
        current.append(character)
      } else if !current.isEmpty {
        words.append(normalised(current))
        current = ""
      }
    }
    if !current.isEmpty { words.append(normalised(current)) }
    return words.filter { !$0.isEmpty }
  }

  /// `true` when `name` holds `cueWords` as whole words, in order, next to
  /// each other.
  static func name(_ name: Name, matches cueWords: [String]) -> Bool {
    guard !cueWords.isEmpty, cueWords.count <= name.words.count else { return false }
    for offset in 0...(name.words.count - cueWords.count)
    where Array(name.words[offset..<(offset + cueWords.count)]) == cueWords {
      return true
    }
    return false
  }

  /// The first capitalised name in `text` that matches `cue`, or `nil`.
  static func firstMatch(of cue: String, in text: String) -> Name? {
    let cueWords = words(ofCue: cue)
    return names(in: text).first { name($0, matches: cueWords) }
  }

  // MARK: - Characters and words

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "'" || character == "’"
      || character == "-"
  }

  /// A word in capitals: at least one letter, no lowercase letter.
  private static func isCapitalised(_ token: String) -> Bool {
    token.contains(where: \.isLetter) && !token.contains(where: \.isLowercase)
  }

  /// Spaces, tabs, periods and quotation marks join the words of one name;
  /// anything else (a comma, `&`, `(`, a line break) ends it.
  private static func joinsName(_ separator: String) -> Bool {
    separator.allSatisfy { character in
      character == " " || character == "\t" || character == "." || character == "\""
        || character == "“" || character == "”"
    }
  }

  /// Uppercased, with surrounding apostrophes and hyphens and a possessive
  /// `'S` removed.
  private static func normalised(_ token: String) -> String {
    var word = token.uppercased()
    for suffix in ["'S", "’S"] where word.hasSuffix(suffix) && word.count > suffix.count {
      word.removeLast(suffix.count)
    }
    let trim = CharacterSet(charactersIn: "'’-")
    return word.trimmingCharacters(in: trim)
  }
}
