import Foundation

/// One scene heading in a Fountain screenplay (SN-1, SN-2).
///
/// A heading is found by ``SceneNumbering/headings(in:)``, which fills in
/// ``lineIndex``, ``offset`` and ``existingNumber``. ``SceneNumbering/assign(_:)``
/// then fills in ``assignedNumber``.
public struct SceneHeading: Sendable, Equatable, Hashable, Codable {
  /// The 0-based index of the heading's line. Lines are split at `\n`; a
  /// `\r` before it belongs to the line ending, so CRLF text has the same
  /// line indexes as LF text.
  public let lineIndex: Int
  /// Where the heading's line starts, in UTF-16 code units from the start of
  /// the text (the unit `NSString` and `NSRange` use).
  public let offset: Int
  /// The number the heading already carries as a trailing Fountain `#n#`,
  /// without the `#` marks, or `nil` when it carries none.
  public let existingNumber: String?
  /// The heading's SN-1 number, set by ``SceneNumbering/assign(_:)``. It is
  /// ``existingNumber`` when there is one (an existing number always wins),
  /// and a new number otherwise. `nil` until `assign(_:)` runs.
  public var assignedNumber: String?

  public init(lineIndex: Int, offset: Int, existingNumber: String?, assignedNumber: String? = nil) {
    self.lineIndex = lineIndex
    self.offset = offset
    self.existingNumber = existingNumber
    self.assignedNumber = assignedNumber
  }

  /// The number to show for this scene: the assigned number, or the existing
  /// one when `assign(_:)` hasn't run.
  public var number: String? { assignedNumber ?? existingNumber }

  /// `true` when SN-1 gives the heading a number it doesn't carry yet, so a
  /// writer would have to append ` #n#` to its line.
  public var needsNumber: Bool { existingNumber == nil && assignedNumber != nil }
}

/// The scene rule and SN-1 numbering, in memory. Nothing here writes a file.
///
/// **Scenes.** A scene starts only at a slugline: a line that begins with
/// `INT./EXT.`, `INT.`, `EXT.` or `EST.` followed by whitespace. Forced `.`
/// lines (`.MUSIC CONTINUES`) never start a scene; they belong to the scene
/// before them. A slugline whose line starts inside a `[[ ]]` note or a
/// `/* */` boneyard is not a heading. An opening `[[` or `/*` with no closing
/// mark is plain text, so a stray opener never hides the scenes after it.
///
/// **SN-1.** An existing number wins. When no heading has a number, they are
/// numbered 1…n. Otherwise an unnumbered heading takes the number before it
/// plus a letter (12A, 12B, … 12Z, 12AA), or `0A`, `0B`, … before the first
/// number, skipping any number already used. Numbering is per text: call it
/// once per episode file.
public enum SceneNumbering {

  // MARK: - Headings

  /// Every scene heading in `text`, in order, with the number it already
  /// carries. ``SceneHeading/assignedNumber`` is `nil` on every result.
  public static func headings(in text: String) -> [SceneHeading] {
    let units = Array(text.utf16)
    let hidden = hiddenRanges(in: units)
    var found: [SceneHeading] = []
    var lineIndex = 0
    var start = 0
    while start <= units.count {
      var end = start
      while end < units.count && units[end] != newline { end += 1 }
      var contentEnd = end
      if contentEnd > start && units[contentEnd - 1] == carriageReturn { contentEnd -= 1 }

      if !hidden.contains(where: { $0.contains(start) }) {
        let line = String(decoding: units[start..<contentEnd], as: UTF16.self)
        if isSlugline(line) {
          found.append(
            SceneHeading(
              lineIndex: lineIndex, offset: start, existingNumber: trailingNumber(of: line)))
        }
      }

      if end >= units.count { break }
      start = end + 1
      lineIndex += 1
    }
    return found
  }

  /// `true` when `line` (without its line ending) is a slugline.
  public static func isSlugline(_ line: String) -> Bool {
    for prefix in sluglinePrefixes where line.hasPrefix(prefix) {
      let rest = line.dropFirst(prefix.count)
      guard let next = rest.first else { return false }
      return next.isWhitespace
    }
    return false
  }

  // MARK: - SN-1

  /// `headings` with ``SceneHeading/assignedNumber`` set on every one by
  /// SN-1. Headings keep their order; existing numbers are never changed.
  public static func assign(_ headings: [SceneHeading]) -> [SceneHeading] {
    var result = headings
    let existing = headings.compactMap(\.existingNumber)

    if existing.isEmpty {
      for index in result.indices {
        result[index].assignedNumber = String(index + 1)
      }
      return result
    }

    var used = Set(existing)
    var root = "0"
    var letters = 0  // how many letters the last number has consumed (A = 1)
    for index in result.indices {
      if let number = result[index].existingNumber {
        result[index].assignedNumber = number
        if let split = splitSuffixed(number) {
          root = split.digits
          letters = letterIndex(split.suffix)
        } else {
          root = number
          letters = 0
        }
        continue
      }
      letters += 1
      while used.contains(root + letterSuffix(letters - 1)) {
        letters += 1
      }
      let number = root + letterSuffix(letters - 1)
      used.insert(number)
      result[index].assignedNumber = number
    }
    return result
  }

  /// The headings of `text` with their SN-1 numbers: `assign(headings(in:))`.
  public static func numberedHeadings(in text: String) -> [SceneHeading] {
    assign(headings(in: text))
  }

  // MARK: - SN-2 lookup

  /// The SN-1 number of the scene that contains `offset` (UTF-16 code units
  /// into the text `headings` came from): the last heading whose line starts
  /// at or before `offset`. `nil` when `offset` comes before the first
  /// heading. Pass headings from ``assign(_:)`` or ``numberedHeadings(in:)``.
  public static func numberForScene(at offset: Int, in headings: [SceneHeading]) -> String? {
    headings.last(where: { $0.offset <= offset })?.number
  }

  /// The SN-1 number of the scene that contains line `lineIndex` (0-based),
  /// or `nil` when the line comes before the first heading.
  public static func numberForScene(atLine lineIndex: Int, in headings: [SceneHeading]) -> String? {
    headings.last(where: { $0.lineIndex <= lineIndex })?.number
  }

  /// The SN-1 number of the scene that contains `offset` in `text`, without
  /// writing anything. Convenience for a single lookup; for many lookups in
  /// one text, call ``numberedHeadings(in:)`` once and use
  /// ``numberForScene(at:in:)``.
  public static func numberForScene(at offset: Int, inText text: String) -> String? {
    numberForScene(at: offset, in: numberedHeadings(in: text))
  }

  // MARK: - Letters

  /// `0 → A`, `25 → Z`, `26 → AA`, …
  static func letterSuffix(_ index: Int) -> String {
    var out = ""
    var value = index + 1
    while value > 0 {
      let remainder = (value - 1) % 26
      value = (value - 1) / 26
      out = String(UnicodeScalar(UInt8(65 + remainder))) + out
    }
    return out
  }

  /// `"" → 0`, `A → 1`, `Z → 26`, `AA → 27`, …
  static func letterIndex(_ letters: String) -> Int {
    var value = 0
    for scalar in letters.unicodeScalars {
      value = value * 26 + Int(scalar.value) - 64
    }
    return value
  }

  // MARK: - Private

  private static let sluglinePrefixes = ["INT./EXT.", "INT.", "EXT.", "EST."]
  private static let newline: UInt16 = 0x0A
  private static let carriageReturn: UInt16 = 0x0D

  /// `12A` → (`12`, `A`); `12` → (`12`, ``); anything else → `nil`.
  private static func splitSuffixed(_ number: String) -> (digits: String, suffix: String)? {
    let digits = number.prefix(while: { $0.isASCII && $0.isNumber })
    guard !digits.isEmpty else { return nil }
    let suffix = number.dropFirst(digits.count)
    guard suffix.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return nil }
    return (digits: String(digits), suffix: String(suffix))
  }

  /// The `n` of a trailing ` #n#` (trailing whitespace allowed), or `nil`.
  private static func trailingNumber(of line: String) -> String? {
    var body = Substring(line)
    while let last = body.last, last.isWhitespace { body.removeLast() }
    guard body.last == "#" else { return nil }
    body.removeLast()
    guard let open = body.lastIndex(of: "#") else { return nil }
    let number = body[body.index(after: open)...]
    guard !number.isEmpty, !number.contains(where: \.isWhitespace) else { return nil }
    guard open > body.startIndex, body[body.index(before: open)].isWhitespace else { return nil }
    return String(number)
  }

  /// UTF-16 ranges covered by `[[ ]]` notes and `/* */` boneyard, scanned in
  /// one pass so an opener inside the other kind is just text.
  private static func hiddenRanges(in units: [UInt16]) -> [Range<Int>] {
    let bracket: UInt16 = 0x5B  // [
    let closeBracket: UInt16 = 0x5D  // ]
    let slash: UInt16 = 0x2F  // /
    let star: UInt16 = 0x2A  // *

    func find(_ first: UInt16, _ second: UInt16, from start: Int) -> Int? {
      var index = start
      while index + 1 < units.count {
        if units[index] == first && units[index + 1] == second { return index }
        index += 1
      }
      return nil
    }

    var ranges: [Range<Int>] = []
    var index = 0
    while index + 1 < units.count {
      let pair = (units[index], units[index + 1])
      let close: (UInt16, UInt16)?
      if pair == (bracket, bracket) {
        close = (closeBracket, closeBracket)
      } else if pair == (slash, star) {
        close = (star, slash)
      } else {
        close = nil
      }
      if let close, let end = find(close.0, close.1, from: index + 2) {
        ranges.append(index..<(end + 2))
        index = end + 2
      } else {
        index += 1
      }
    }
    return ranges
  }
}
