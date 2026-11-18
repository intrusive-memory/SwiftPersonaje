import Foundation
import SwiftCompartido

// MARK: - Plan

/// How a screenplay's bytes are encoded. Only encodings that round-trip
/// byte for byte are planned; anything else is skipped.
public enum SceneNumberTextEncoding: String, Sendable, Codable, Hashable {
  /// UTF-8 with no byte-order mark.
  case utf8
  /// UTF-8 starting with the `EF BB BF` byte-order mark.
  case utf8WithBOM
  /// UTF-16, little-endian, starting with the `FF FE` byte-order mark.
  case utf16LittleEndian
  /// UTF-16, big-endian, starting with the `FE FF` byte-order mark.
  case utf16BigEndian

  /// The byte-order mark the file starts with (empty for plain UTF-8).
  public var byteOrderMark: [UInt8] {
    switch self {
    case .utf8: []
    case .utf8WithBOM: [0xEF, 0xBB, 0xBF]
    case .utf16LittleEndian: [0xFF, 0xFE]
    case .utf16BigEndian: [0xFE, 0xFF]
    }
  }

  /// `text` in this encoding, without the byte-order mark.
  public func encode(_ text: String) -> [UInt8] {
    switch self {
    case .utf8, .utf8WithBOM:
      return Array(text.utf8)
    case .utf16LittleEndian:
      var bytes: [UInt8] = []
      bytes.reserveCapacity(text.utf16.count * 2)
      for unit in text.utf16 {
        bytes.append(UInt8(unit & 0xFF))
        bytes.append(UInt8(unit >> 8))
      }
      return bytes
    case .utf16BigEndian:
      var bytes: [UInt8] = []
      bytes.reserveCapacity(text.utf16.count * 2)
      for unit in text.utf16 {
        bytes.append(UInt8(unit >> 8))
        bytes.append(UInt8(unit & 0xFF))
      }
      return bytes
    }
  }

  /// The whole file for `text`: the byte-order mark, then the encoded text.
  public func fileData(for text: String) -> Data {
    Data(byteOrderMark + encode(text))
  }

  /// How many bytes `text` takes in this encoding (no byte-order mark).
  func byteCount(of text: String) -> Int {
    switch self {
    case .utf8, .utf8WithBOM: text.utf8.count
    case .utf16LittleEndian, .utf16BigEndian: text.utf16.count * 2
    }
  }

  /// The encoding of `data` and its text, or `nil` when the bytes don't
  /// decode and re-encode to exactly the same bytes. A UTF-16 file needs a
  /// byte-order mark; without one the bytes are read as UTF-8.
  public static func decode(_ data: Data) -> (encoding: SceneNumberTextEncoding, text: String)? {
    let bytes = [UInt8](data)
    let candidate: SceneNumberTextEncoding
    if bytes.starts(with: SceneNumberTextEncoding.utf8WithBOM.byteOrderMark) {
      candidate = .utf8WithBOM
    } else if bytes.starts(with: SceneNumberTextEncoding.utf16LittleEndian.byteOrderMark) {
      candidate = .utf16LittleEndian
    } else if bytes.starts(with: SceneNumberTextEncoding.utf16BigEndian.byteOrderMark) {
      candidate = .utf16BigEndian
    } else {
      candidate = .utf8
    }

    let body = Array(bytes.dropFirst(candidate.byteOrderMark.count))
    let text: String
    switch candidate {
    case .utf8, .utf8WithBOM:
      text = String(decoding: body, as: UTF8.self)
    case .utf16LittleEndian, .utf16BigEndian:
      guard body.count % 2 == 0 else { return nil }
      var units: [UInt16] = []
      units.reserveCapacity(body.count / 2)
      var index = 0
      while index < body.count {
        let first = UInt16(body[index])
        let second = UInt16(body[index + 1])
        units.append(
          candidate == .utf16LittleEndian ? first | (second << 8) : (first << 8) | second)
        index += 2
      }
      text = String(decoding: units, as: UTF16.self)
    }
    // Lossy decoding (invalid UTF-8, lone surrogates) shows up here.
    guard candidate.encode(text) == body else { return nil }
    return (candidate, text)
  }
}

/// The line endings a screenplay uses.
public enum SceneNumberLineEnding: String, Sendable, Codable, Hashable {
  /// Every line ends in `\n`.
  case lf
  /// Every line ends in `\r\n`.
  case crlf
  /// Both `\n` and `\r\n` appear. Each line keeps its own ending.
  case mixed
  /// The text has no line break at all (a single line).
  case none

  /// The line endings in `text`, or `nil` for classic Mac text, where a
  /// lone `\r` ends a line (SN-1 splits lines at `\n` only, so it can't be
  /// numbered safely).
  public static func detect(in text: String) -> SceneNumberLineEnding? {
    var lf = 0
    var crlf = 0
    var loneCR = 0
    var previous: UInt16 = 0
    for unit in text.utf16 {
      if unit == 0x0A {
        if previous == 0x0D { crlf += 1 } else { lf += 1 }
      } else if previous == 0x0D {
        loneCR += 1
      }
      previous = unit
    }
    if previous == 0x0D { loneCR += 1 }
    if loneCR > 0 && lf == 0 && crlf == 0 { return nil }
    switch (lf > 0, crlf > 0) {
    case (true, true): return .mixed
    case (true, false): return .lf
    case (false, true): return .crlf
    case (false, false): return SceneNumberLineEnding.none
    }
  }
}

/// One line SN-3 changes: an unnumbered slugline that gets ` #n#` appended
/// before its line ending.
public struct SceneNumberChange: Sendable, Equatable, Hashable {
  /// The heading, with its SN-1 ``SceneHeading/assignedNumber``.
  public let heading: SceneHeading
  /// The number appended, without the `#` marks.
  public let number: String
  /// The exact text appended: `" #" + number + "#"`.
  public let suffix: String
  /// The line before the change, without its line ending.
  public let originalLine: String
  /// The line after the change, without its line ending.
  public let newLine: String
  /// Where ``suffix`` is inserted, in bytes from the start of the original
  /// file (byte-order mark included).
  public let byteOffset: Int

  /// The 0-based line index of the change.
  public var lineIndex: Int { heading.lineIndex }

  public init(
    heading: SceneHeading, number: String, suffix: String, originalLine: String, newLine: String,
    byteOffset: Int
  ) {
    self.heading = heading
    self.number = number
    self.suffix = suffix
    self.originalLine = originalLine
    self.newLine = newLine
    self.byteOffset = byteOffset
  }
}

/// What SN-3 would do to one screenplay file, built in memory and checked by
/// SN-5 (``SceneNumberValidator``). Nothing is written.
///
/// It carries everything a writer needs: the file, the bytes read, the bytes
/// to write and the headings that change.
public struct SceneNumberPlan: Sendable, Equatable {

  public enum Status: Sendable, Equatable, Hashable {
    /// The file was read and planned. ``SceneNumberPlan/changes`` may be empty
    /// when every heading is already numbered.
    case planned
    /// The file is left alone, for `reason`.
    case skipped(reason: String)
  }

  /// The screenplay file.
  public let file: URL
  public let status: Status
  /// The file's encoding; `nil` when the file was skipped before decoding.
  public let encoding: SceneNumberTextEncoding?
  /// The file's line endings; `nil` when the file was skipped before decoding.
  public let lineEnding: SceneNumberLineEnding?
  /// The bytes read from ``file`` (empty when skipped before reading).
  public let originalData: Data
  /// The bytes to write: ``originalData`` with each suffix inserted.
  public let newData: Data
  /// ``originalData`` decoded.
  public let originalText: String
  /// ``newData`` decoded.
  public let newText: String
  /// The changed lines, in line order.
  public let changes: [SceneNumberChange]

  public init(
    file: URL, status: Status, encoding: SceneNumberTextEncoding?,
    lineEnding: SceneNumberLineEnding?, originalData: Data, newData: Data, originalText: String,
    newText: String, changes: [SceneNumberChange]
  ) {
    self.file = file
    self.status = status
    self.encoding = encoding
    self.lineEnding = lineEnding
    self.originalData = originalData
    self.newData = newData
    self.originalText = originalText
    self.newText = newText
    self.changes = changes
  }

  /// A plan that leaves `file` alone.
  public static func skipped(_ file: URL, reason: String, originalData: Data = Data())
    -> SceneNumberPlan
  {
    SceneNumberPlan(
      file: file, status: .skipped(reason: reason), encoding: nil, lineEnding: nil,
      originalData: originalData, newData: originalData, originalText: "", newText: "",
      changes: [])
  }

  /// `true` when writing the plan would change the file.
  public var hasChanges: Bool { !changes.isEmpty }

  /// Why the file is skipped, or `nil` when it was planned.
  public var skipReason: String? {
    if case .skipped(let reason) = status { return reason }
    return nil
  }
}

/// The file could not be read.
public enum SceneNumberPlanError: Error, Sendable, Equatable {
  case unreadable(path: String, reason: String)
}

// MARK: - Writer (plan half)

/// SN-3: appends ` #n#` to each unnumbered slugline, as a line-level edit of
/// the file's own bytes. The screenplay is never re-serialised; every other
/// byte is kept as read.
public enum SceneNumberWriter {

  /// The SN-3 plan for `file`, checked by SN-5 before it is returned.
  ///
  /// Only `.fountain` files are planned; any other file returns a skipped
  /// plan without being read. A `.fountain` file whose bytes aren't UTF-8 or
  /// UTF-16 with a byte-order mark, or that uses classic Mac `\r` line
  /// endings, is skipped too. A fully numbered file returns a plan with no
  /// changes.
  ///
  /// - Throws: ``SceneNumberPlanError`` when the file can't be read, and
  ///   ``SceneNumberValidationError`` when the plan fails an SN-5 check.
  public static func plan(for file: URL) throws -> SceneNumberPlan {
    guard file.pathExtension.lowercased() == "fountain" else {
      return .skipped(file, reason: "not a .fountain file")
    }
    let data: Data
    do {
      data = try Data(contentsOf: file)
    } catch {
      throw SceneNumberPlanError.unreadable(path: file.path, reason: String(describing: error))
    }
    return try plan(for: file, data: data)
  }

  /// The SN-3 plan for `data`, the bytes of `file`, checked by SN-5. A
  /// writer re-plans from freshly read bytes with this before writing.
  public static func plan(for file: URL, data: Data) throws -> SceneNumberPlan {
    guard let decoded = SceneNumberTextEncoding.decode(data) else {
      return .skipped(
        file, reason: "not UTF-8, or UTF-16 with a byte-order mark", originalData: data)
    }
    guard let lineEnding = SceneNumberLineEnding.detect(in: decoded.text) else {
      return .skipped(file, reason: "classic Mac (\\r) line endings", originalData: data)
    }
    let toNumber = SceneNumbering.numberedHeadings(in: decoded.text).filter(\.needsNumber)
    let plan = build(
      file: file, data: data, encoding: decoded.encoding, text: decoded.text,
      lineEnding: lineEnding, numbering: toNumber)
    try SceneNumberValidator.validate(plan)
    return plan
  }

  /// A plan that appends ` #n#` to the line of each of `headings` (using its
  /// ``SceneHeading/assignedNumber``), unvalidated. ``plan(for:)`` passes the
  /// headings SN-1 says need a number.
  static func build(
    file: URL, data: Data, encoding: SceneNumberTextEncoding, text: String,
    lineEnding: SceneNumberLineEnding, numbering headings: [SceneHeading]
  ) -> SceneNumberPlan {
    var byLine: [Int: SceneHeading] = [:]
    for heading in headings where byLine[heading.lineIndex] == nil {
      byLine[heading.lineIndex] = heading
    }

    var newText = ""
    var changes: [SceneNumberChange] = []
    var byteOffset = encoding.byteOrderMark.count
    for (index, line) in SceneNumberLine.split(text).enumerated() {
      let contentBytes = encoding.byteCount(of: line.content)
      if let heading = byLine[index], let number = heading.assignedNumber {
        let suffix = " #\(number)#"
        let newLine = line.content + suffix
        changes.append(
          SceneNumberChange(
            heading: heading, number: number, suffix: suffix, originalLine: line.content,
            newLine: newLine, byteOffset: byteOffset + contentBytes))
        newText += newLine
      } else {
        newText += line.content
      }
      newText += line.ending
      byteOffset += contentBytes + encoding.byteCount(of: line.ending)
    }

    return SceneNumberPlan(
      file: file, status: .planned, encoding: encoding, lineEnding: lineEnding,
      originalData: data, newData: encoding.fileData(for: newText), originalText: text,
      newText: newText, changes: changes)
  }
}

// MARK: - SN-5

/// Which SN-5 check failed, with what it found.
public enum SceneNumberValidationError: Error, Sendable, Equatable, CustomStringConvertible {
  /// (a) Removing the appended suffixes from the new bytes doesn't give the
  /// original bytes exactly.
  case suffixStrip(path: String, detail: String)
  /// (b) The line count changed, or a changed line isn't an unnumbered SN-1
  /// slugline with exactly ` #n#` appended. `lineIndex` is 0-based.
  case changedLines(path: String, lineIndex: Int?, detail: String)
  /// (c) SwiftCompartido parses the new text differently from the old one
  /// (beyond scene numbers), or a slugline is left without a number.
  case parseMismatch(path: String, detail: String)

  /// The names of the three checks.
  public enum Check: String, Sendable, Hashable, CaseIterable {
    case suffixStrip
    case changedLines
    case parseMismatch
  }

  /// The check that failed.
  public var check: Check {
    switch self {
    case .suffixStrip: .suffixStrip
    case .changedLines: .changedLines
    case .parseMismatch: .parseMismatch
    }
  }

  public var description: String {
    switch self {
    case .suffixStrip(let path, let detail):
      return "\(path): suffix-strip check failed: \(detail)"
    case .changedLines(let path, let lineIndex, let detail):
      if let lineIndex {
        return "\(path): changed-lines check failed at line \(lineIndex + 1): \(detail)"
      }
      return "\(path): changed-lines check failed: \(detail)"
    case .parseMismatch(let path, let detail):
      return "\(path): parse check failed: \(detail)"
    }
  }
}

/// SN-5: the checks a scene-number plan must pass before anything is
/// written. ``SceneNumberWriter/plan(for:)`` runs them; they are public so a
/// writer can re-run them, and a test can run them on a damaged plan.
public enum SceneNumberValidator {

  /// Runs checks (a), (b) and (c) in order and throws the first failure. A
  /// skipped plan passes: it writes nothing.
  public static func validate(_ plan: SceneNumberPlan) throws(SceneNumberValidationError) {
    guard plan.status == .planned else { return }
    try checkSuffixStrip(plan)
    try checkChangedLines(plan)
    try checkParse(plan)
  }

  /// (a) The texts are the decoded bytes, and removing each change's suffix
  /// from the new bytes at its offset gives the original bytes exactly.
  public static func checkSuffixStrip(_ plan: SceneNumberPlan) throws(SceneNumberValidationError) {
    let path = plan.file.path
    func fail(_ detail: String) -> SceneNumberValidationError {
      .suffixStrip(path: path, detail: detail)
    }
    guard let encoding = plan.encoding else { throw fail("a planned file has no encoding") }
    guard encoding.fileData(for: plan.originalText) == plan.originalData else {
      throw fail("the original text is not the original bytes")
    }
    guard encoding.fileData(for: plan.newText) == plan.newData else {
      throw fail("the new text is not the new bytes")
    }

    let original = [UInt8](plan.originalData)
    let new = [UInt8](plan.newData)
    var stripped: [UInt8] = []
    stripped.reserveCapacity(original.count)
    var cursor = 0  // in `new`
    var previousOffset = 0  // in `original`
    for change in plan.changes.sorted(by: { $0.byteOffset < $1.byteOffset }) {
      guard change.byteOffset >= previousOffset, change.byteOffset <= original.count else {
        throw fail("suffix offset \(change.byteOffset) is out of order or out of range")
      }
      let keep = change.byteOffset - previousOffset
      let suffix = encoding.encode(change.suffix)
      guard cursor + keep + suffix.count <= new.count else {
        throw fail("the new bytes end before the suffix at offset \(change.byteOffset)")
      }
      stripped.append(contentsOf: new[cursor..<(cursor + keep)])
      guard Array(new[(cursor + keep)..<(cursor + keep + suffix.count)]) == suffix else {
        throw fail("\"\(change.suffix)\" is not at offset \(change.byteOffset)")
      }
      cursor += keep + suffix.count
      previousOffset = change.byteOffset
    }
    stripped.append(contentsOf: new[cursor...])
    guard stripped == original else {
      throw fail("the new bytes without the suffixes differ from the original bytes")
    }
  }

  /// (b) The line count is the same, and every changed line is an
  /// unnumbered SN-1 slugline with exactly its ` #n#` appended before the
  /// same line ending.
  public static func checkChangedLines(_ plan: SceneNumberPlan) throws(SceneNumberValidationError) {
    let path = plan.file.path
    func fail(_ line: Int?, _ detail: String) -> SceneNumberValidationError {
      .changedLines(path: path, lineIndex: line, detail: detail)
    }
    let old = SceneNumberLine.split(plan.originalText)
    let new = SceneNumberLine.split(plan.newText)
    guard old.count == new.count else {
      throw fail(nil, "\(old.count) lines became \(new.count)")
    }

    var changeByLine: [Int: SceneNumberChange] = [:]
    for change in plan.changes {
      guard changeByLine[change.lineIndex] == nil else {
        throw fail(change.lineIndex, "the line is changed twice")
      }
      guard change.lineIndex >= 0, change.lineIndex < old.count else {
        throw fail(change.lineIndex, "the change is outside the file")
      }
      changeByLine[change.lineIndex] = change
    }

    var unnumbered: Set<Int> = []
    for heading in SceneNumbering.headings(in: plan.originalText)
    where heading.existingNumber == nil {
      unnumbered.insert(heading.lineIndex)
    }
    var newNumbers: [Int: String] = [:]
    for heading in SceneNumbering.headings(in: plan.newText) {
      if let number = heading.existingNumber { newNumbers[heading.lineIndex] = number }
    }

    for index in old.indices {
      let before = old[index]
      let after = new[index]
      let unchanged = same(before.content, after.content) && same(before.ending, after.ending)
      guard let change = changeByLine[index] else {
        if unchanged { continue }
        throw fail(index, "the line changed but no change lists it")
      }
      if unchanged { throw fail(index, "a change lists the line but it is unchanged") }
      guard unnumbered.contains(index) else {
        throw fail(index, "the changed line is not an unnumbered slugline")
      }
      guard same(before.ending, after.ending) else {
        throw fail(index, "the line ending changed")
      }
      guard isValidNumber(change.number), same(change.suffix, " #\(change.number)#") else {
        throw fail(index, "\"\(change.suffix)\" is not a scene-number suffix")
      }
      guard same(after.content, before.content + change.suffix) else {
        throw fail(index, "the new line is not the old line with \"\(change.suffix)\" appended")
      }
      guard same(change.originalLine, before.content), same(change.newLine, after.content) else {
        throw fail(index, "the change's lines don't match the text")
      }
      guard newNumbers[index] == change.number else {
        throw fail(index, "the new line doesn't read back as scene \(change.number)")
      }
    }
  }

  /// (c) SwiftCompartido parses old and new text to the same elements (count,
  /// types, text) once scene numbers are set aside; each appended number is
  /// read as a scene number; and every SN-1 slugline in the new text carries
  /// a number.
  public static func checkParse(_ plan: SceneNumberPlan) throws(SceneNumberValidationError) {
    let path = plan.file.path
    func fail(_ detail: String) -> SceneNumberValidationError {
      .parseMismatch(path: path, detail: detail)
    }
    let old = FountainParser(string: plan.originalText).elements
    let new = FountainParser(string: plan.newText).elements
    guard old.count == new.count else {
      throw fail("\(old.count) elements became \(new.count)")
    }

    var gained = 0
    for index in old.indices {
      let before = old[index]
      let after = new[index]
      guard before.elementType == after.elementType else {
        throw fail("element \(index) changed type")
      }
      let isHeading = before.elementType == .sceneHeading
      // A heading's text is its line without the `#n#`; the space before the
      // appended number stays, so trailing whitespace is set aside.
      let textBefore =
        isHeading ? trimmingTrailingWhitespace(before.elementText) : before.elementText
      let textAfter = isHeading ? trimmingTrailingWhitespace(after.elementText) : after.elementText
      guard textBefore == textAfter else {
        throw fail("element \(index) changed text")
      }
      if let number = before.sceneNumber, after.sceneNumber != number {
        throw fail("element \(index) lost its scene number \(number)")
      }
      if before.sceneNumber == nil && after.sceneNumber != nil { gained += 1 }
    }
    guard gained == plan.changes.count else {
      throw fail("\(plan.changes.count) numbers were appended but \(gained) parse as scene numbers")
    }

    let left = SceneNumbering.headings(in: plan.newText).filter { $0.existingNumber == nil }
    if let first = left.first {
      throw fail("the slugline on line \(first.lineIndex + 1) has no scene number")
    }
  }

  // MARK: - Private

  private static func same(_ a: String, _ b: String) -> Bool {
    a.utf16.elementsEqual(b.utf16)
  }

  private static func isValidNumber(_ number: String) -> Bool {
    !number.isEmpty && !number.contains("#") && !number.contains(where: \.isWhitespace)
  }

  private static func trimmingTrailingWhitespace(_ text: String) -> String {
    var result = Substring(text)
    while let last = result.last, last.isWhitespace { result.removeLast() }
    return String(result)
  }
}

// MARK: - Lines

/// A line of text and its ending, split the way ``SceneNumbering`` splits
/// lines: at `\n`, with a `\r` before it part of the ending.
struct SceneNumberLine: Sendable, Equatable {
  /// The line without its ending.
  let content: String
  /// `"\n"`, `"\r\n"`, or `""` for the last line.
  let ending: String

  static func split(_ text: String) -> [SceneNumberLine] {
    let units = Array(text.utf16)
    var lines: [SceneNumberLine] = []
    var start = 0
    while true {
      var end = start
      while end < units.count && units[end] != 0x0A { end += 1 }
      var contentEnd = end
      if contentEnd > start && units[contentEnd - 1] == 0x0D { contentEnd -= 1 }
      let content = String(decoding: units[start..<contentEnd], as: UTF16.self)
      let ending = String(decoding: units[contentEnd..<min(end + 1, units.count)], as: UTF16.self)
      lines.append(SceneNumberLine(content: content, ending: ending))
      if end >= units.count { break }
      start = end + 1
    }
    return lines
  }
}

// MARK: - Writer (write half)

/// What ``SceneNumberWriter/write(_:backupRoot:relativeTo:)`` did to one file.
public struct SceneNumberResult: Sendable, Equatable {

  public enum Outcome: Sendable, Equatable, Hashable {
    /// The new bytes were written and read back equal; the original is in
    /// ``SceneNumberResult/backup``.
    case written
    /// The plan had no changes (every heading already numbered): nothing was
    /// written and no backup was made.
    case unchanged
    /// The plan skipped the file, for `reason`: nothing was written and no
    /// backup was made.
    case skipped(reason: String)
  }

  /// The screenplay file.
  public let file: URL
  public let outcome: Outcome
  /// The byte-equal copy of the original, or `nil` when nothing was written.
  public let backup: URL?
  /// The headings numbered (empty unless ``outcome`` is ``Outcome/written``).
  public let changes: [SceneNumberChange]

  public init(file: URL, outcome: Outcome, backup: URL?, changes: [SceneNumberChange]) {
    self.file = file
    self.outcome = outcome
    self.backup = backup
    self.changes = changes
  }

  /// `true` when the file on disk now holds the plan's new bytes.
  public var wroteFile: Bool { outcome == .written }
}

/// Why ``SceneNumberWriter/write(_:backupRoot:relativeTo:)`` didn't write a
/// file. Unless the case says otherwise, the file on disk holds its original
/// bytes when the error is thrown.
public enum SceneNumberWriteError: Error, Sendable, Equatable, CustomStringConvertible {
  /// The file couldn't be read before writing. Nothing was written.
  case unreadable(file: URL, reason: String)
  /// The file's bytes on disk are no longer the plan's ``SceneNumberPlan/originalData``
  /// (it changed after it was planned). Nothing was written; re-plan it.
  case changedOnDisk(file: URL)
  /// The file isn't inside the project root it was to be backed up relative
  /// to. Nothing was written and no backup was made.
  case outsideProject(file: URL, projectRoot: URL)
  /// Something already exists at the backup path. Nothing was written, and
  /// the existing item was left alone.
  case backupExists(file: URL, backup: URL)
  /// The backup couldn't be made. Nothing was written.
  case backupFailed(file: URL, backup: URL, reason: String)
  /// SN-4: the backup's bytes differ from the original's. Nothing was written.
  case backupMismatch(file: URL, backup: URL)
  /// The atomic write threw. The original bytes are on disk (restored from
  /// the backup if the failed write had touched them).
  case writeFailed(file: URL, reason: String)
  /// SN-6: the bytes read back after the write weren't the validated new
  /// bytes. The original was restored from the backup and read back equal.
  case verifyFailed(file: URL)
  /// A write went wrong and restoring the original from `backup` failed too.
  /// **The file on disk may be damaged**; `backup` holds the original bytes.
  case restoreFailed(file: URL, backup: URL, reason: String)

  public var description: String {
    switch self {
    case .unreadable(let file, let reason):
      return "\(file.path): can't be read: \(reason)"
    case .changedOnDisk(let file):
      return "\(file.path): changed on disk since it was planned; nothing written"
    case .outsideProject(let file, let projectRoot):
      return "\(file.path): not inside the project \(projectRoot.path)"
    case .backupExists(let file, let backup):
      return "\(file.path): a backup already exists at \(backup.path); nothing written"
    case .backupFailed(let file, let backup, let reason):
      return "\(file.path): backup to \(backup.path) failed: \(reason); nothing written"
    case .backupMismatch(let file, let backup):
      return "\(file.path): the backup at \(backup.path) differs from the original; nothing written"
    case .writeFailed(let file, let reason):
      return "\(file.path): write failed: \(reason); the original is in place"
    case .verifyFailed(let file):
      return
        "\(file.path): the written bytes didn't read back as planned; the original was restored"
    case .restoreFailed(let file, let backup, let reason):
      return
        "\(file.path): restore failed: \(reason); the file may be damaged, the original is at \(backup.path)"
    }
  }
}

extension SceneNumberWriter {

  /// Writes `plan` to its file, safely.
  ///
  /// 1. A skipped plan, or one with no changes, returns at once: nothing is
  ///    read or written and no backup (or backup directory) is made.
  /// 2. The plan is re-checked by SN-5, and the file's bytes on disk must
  ///    still equal ``SceneNumberPlan/originalData``; otherwise it throws
  ///    ``SceneNumberWriteError/changedOnDisk(file:)`` and writes nothing.
  /// 3. SN-4: the file is copied to `backupRoot/<relative path>` and the copy
  ///    is read back and must equal the original bytes.
  /// 4. The plan's ``SceneNumberPlan/newData`` is written atomically.
  /// 5. SN-6: the file is read back; if it isn't `newData` byte for byte, the
  ///    original is restored from the backup and the write throws
  ///    ``SceneNumberWriteError/verifyFailed(file:)``.
  ///
  /// **The relative path.** With `projectRoot`, the backup goes to
  /// `backupRoot` plus the file's path relative to `projectRoot` (for
  /// `<project>/episodes/e1.fountain`, `backupRoot/episodes/e1.fountain`);
  /// a file outside `projectRoot` throws
  /// ``SceneNumberWriteError/outsideProject(file:projectRoot:)``. Without it,
  /// the backup is `backupRoot/<file name>`, so two files with the same name
  /// in different folders need a `projectRoot` (the second one throws
  /// ``SceneNumberWriteError/backupExists(file:backup:)``). Paths are
  /// compared after standardising and resolving symbolic links.
  ///
  /// The writer never chooses `backupRoot`, never deletes a backup and never
  /// overwrites anything already in `backupRoot`.
  ///
  /// - Throws: ``SceneNumberWriteError``, or ``SceneNumberValidationError``
  ///   when the plan fails SN-5.
  @discardableResult
  public static func write(
    _ plan: SceneNumberPlan, backupRoot: URL, relativeTo projectRoot: URL? = nil
  )
    throws -> SceneNumberResult
  {
    try write(
      plan, backupRoot: backupRoot, relativeTo: projectRoot,
      fileSystem: DefaultSceneNumberFileSystem())
  }

  /// ``write(_:backupRoot:relativeTo:)`` through `fileSystem` (a test seam).
  @discardableResult
  static func write(
    _ plan: SceneNumberPlan, backupRoot: URL, relativeTo projectRoot: URL?,
    fileSystem fs: some SceneNumberFileSystem
  ) throws -> SceneNumberResult {
    let file = plan.file
    if case .skipped(let reason) = plan.status {
      return SceneNumberResult(
        file: file, outcome: .skipped(reason: reason), backup: nil, changes: [])
    }
    guard plan.hasChanges else {
      return SceneNumberResult(file: file, outcome: .unchanged, backup: nil, changes: [])
    }

    try SceneNumberValidator.validate(plan)
    let backup = try backupURL(for: file, backupRoot: backupRoot, projectRoot: projectRoot)
    try requireOriginal(plan, fs)

    // SN-4: back up, and check the copy.
    guard !fs.itemExists(at: backup) else {
      throw SceneNumberWriteError.backupExists(file: file, backup: backup)
    }
    do {
      try fs.createDirectory(at: backup.deletingLastPathComponent())
      try fs.copyItem(at: file, to: backup)
    } catch {
      throw SceneNumberWriteError.backupFailed(
        file: file, backup: backup, reason: String(describing: error))
    }
    guard (try? fs.contents(of: backup)) == plan.originalData else {
      throw SceneNumberWriteError.backupMismatch(file: file, backup: backup)
    }

    // The file may have changed while the backup was made.
    try requireOriginal(plan, fs)

    do {
      try fs.writeAtomically(plan.newData, to: file)
    } catch {
      if (try? fs.contents(of: file)) != plan.originalData {
        try restore(plan, from: backup, fs)
      }
      throw SceneNumberWriteError.writeFailed(file: file, reason: String(describing: error))
    }

    // SN-6: read back and compare to the validated bytes.
    guard (try? fs.contents(of: file)) == plan.newData else {
      try restore(plan, from: backup, fs)
      throw SceneNumberWriteError.verifyFailed(file: file)
    }
    return SceneNumberResult(file: file, outcome: .written, backup: backup, changes: plan.changes)
  }

  /// Where `file` is backed up: `backupRoot` plus its path relative to
  /// `projectRoot`, or plus its name when there is no `projectRoot`.
  static func backupURL(for file: URL, backupRoot: URL, projectRoot: URL?) throws -> URL {
    let relative: [String]
    if let projectRoot {
      let rootParts = projectRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
      let fileParts = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
      guard fileParts.count > rootParts.count, Array(fileParts.prefix(rootParts.count)) == rootParts
      else {
        throw SceneNumberWriteError.outsideProject(file: file, projectRoot: projectRoot)
      }
      relative = Array(fileParts.dropFirst(rootParts.count))
    } else {
      relative = [file.lastPathComponent]
    }
    var url = backupRoot
    for (index, part) in relative.enumerated() {
      url.appendPathComponent(part, isDirectory: index < relative.count - 1)
    }
    return url
  }

  /// Throws unless the file's bytes on disk are the plan's original bytes.
  private static func requireOriginal(_ plan: SceneNumberPlan, _ fs: some SceneNumberFileSystem)
    throws
  {
    let current: Data
    do {
      current = try fs.contents(of: plan.file)
    } catch {
      throw SceneNumberWriteError.unreadable(file: plan.file, reason: String(describing: error))
    }
    guard current == plan.originalData else {
      throw SceneNumberWriteError.changedOnDisk(file: plan.file)
    }
  }

  /// Puts the backup's bytes back in the file and reads them back. Throws
  /// ``SceneNumberWriteError/restoreFailed(file:backup:reason:)`` unless the
  /// file then holds the original bytes.
  private static func restore(
    _ plan: SceneNumberPlan, from backup: URL, _ fs: some SceneNumberFileSystem
  ) throws {
    let file = plan.file
    func fail(_ reason: String) -> SceneNumberWriteError {
      .restoreFailed(file: file, backup: backup, reason: reason)
    }
    let saved: Data
    do {
      saved = try fs.contents(of: backup)
    } catch {
      throw fail("the backup can't be read: \(error)")
    }
    guard saved == plan.originalData else { throw fail("the backup differs from the original") }
    do {
      try fs.writeAtomically(saved, to: file)
    } catch {
      throw fail("the write threw: \(error)")
    }
    guard (try? fs.contents(of: file)) == plan.originalData else {
      throw fail("the restored file doesn't read back as the original")
    }
  }
}
