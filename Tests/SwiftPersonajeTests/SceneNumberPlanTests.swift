import Foundation
import Testing

@testable import SwiftPersonaje

/// SN-3 and SN-5: the scene-number plan, built and checked in memory.
/// Synthetic, invented screenplays only; nothing is written back.
@Suite("Scene-number plan and validation (SN-3, SN-5)")
struct SceneNumberPlanTests {

  // MARK: - Helpers

  /// A two-scene screenplay with `ending` between lines.
  private func workshop(_ ending: String = "\n") -> String {
    [
      "Title: Lamps", "", "INT. WORKSHOP - DAY", "", "MARA", "Hand me that.", "",
      "EXT. YARD - NIGHT", "", "Rain on the tin roof.", "",
    ].joined(separator: ending)
  }

  /// Writes `data` to a fresh temp directory as `name`.
  private func write(_ data: Data, named name: String) throws -> URL {
    let url = try Synthetic.makeDirectory().appendingPathComponent(name)
    try data.write(to: url)
    return url
  }

  private func write(_ text: String, named name: String = "episode.fountain") throws -> URL {
    try write(Data(text.utf8), named: name)
  }

  /// The planned text with every appended ` #n#` removed, worked out from the
  /// text alone (not the validator), as UTF-8 bytes.
  private func strippedBytes(_ plan: SceneNumberPlan) -> Data {
    var text = plan.newText
    for change in plan.changes {
      text = text.replacingOccurrences(of: change.suffix, with: "")
    }
    return Data(text.utf8)
  }

  /// The check `plan` fails, or `nil` when it passes.
  private func failedCheck(_ plan: SceneNumberPlan) -> SceneNumberValidationError.Check? {
    do throws(SceneNumberValidationError) {
      try SceneNumberValidator.validate(plan)
      return nil
    } catch {
      return error.check
    }
  }

  // MARK: - SN-3

  @Test("LF: each unnumbered slugline gets #n# before its newline")
  func lfEndings() throws {
    let original = workshop()
    let url = try write(original)
    let plan = try SceneNumberWriter.plan(for: url)

    #expect(plan.status == .planned)
    #expect(plan.encoding == .utf8)
    #expect(plan.lineEnding == .lf)
    #expect(plan.changes.map(\.number) == ["1", "2"])
    #expect(plan.changes.map(\.lineIndex) == [2, 7])
    #expect(
      plan.newText
        == "Title: Lamps\n\nINT. WORKSHOP - DAY #1#\n\nMARA\nHand me that.\n\n"
        + "EXT. YARD - NIGHT #2#\n\nRain on the tin roof.\n")
    let onDisk = try Data(contentsOf: url)
    #expect(plan.originalData == onDisk)
    #expect(strippedBytes(plan) == plan.originalData)
  }

  @Test("CRLF: the suffix goes before \\r\\n and every ending stays CRLF")
  func crlfEndings() throws {
    let original = workshop("\r\n")
    let plan = try SceneNumberWriter.plan(for: try write(original))

    #expect(plan.lineEnding == .crlf)
    #expect(plan.changes.map(\.number) == ["1", "2"])
    #expect(plan.newText.contains("INT. WORKSHOP - DAY #1#\r\n"))
    #expect(plan.newText.contains("EXT. YARD - NIGHT #2#\r\n"))
    let units = Array(plan.newText.utf16)
    let bareLineFeeds = units.indices.filter {
      units[$0] == 0x0A && ($0 == 0 || units[$0 - 1] != 0x0D)
    }
    #expect(bareLineFeeds.isEmpty)
    #expect(strippedBytes(plan) == plan.originalData)
  }

  @Test("No final newline: the last slugline is numbered at the end of the file")
  func noFinalNewline() throws {
    let original = "Title: Lamps\n\nINT. WORKSHOP - DAY\n\nMARA\nHand me that.\n\nEXT. YARD - NIGHT"
    let plan = try SceneNumberWriter.plan(for: try write(original))

    #expect(plan.changes.map(\.number) == ["1", "2"])
    #expect(plan.newText.hasSuffix("EXT. YARD - NIGHT #2#"))
    #expect(strippedBytes(plan) == plan.originalData)
  }

  @Test("Trailing spaces and tabs on a heading are kept; the number goes after them")
  func trailingWhitespaceOnHeading() throws {
    let original = "Title: Lamps\n\nINT. WORKSHOP - DAY  \t\n\nMARA\nHand me that.\n"
    let plan = try SceneNumberWriter.plan(for: try write(original))

    #expect(plan.changes.map(\.newLine) == ["INT. WORKSHOP - DAY  \t #1#"])
    #expect(plan.changes.map(\.originalLine) == ["INT. WORKSHOP - DAY  \t"])
    #expect(strippedBytes(plan) == plan.originalData)
  }

  @Test("Non-ASCII text: byte offsets count UTF-8 bytes, not characters")
  func nonASCIIText() throws {
    let original =
      "Title: Café Niña\n\nINT. CAFÉ “LA NIÑA” - DÍA\n\nJOSÉ\n¿Qué tal, señor? “Bien.”\n\n"
      + "EXT. PLAZA DE LA ESTACIÓN - NOCHE\n\nLlueve.\n"
    let url = try write(original)
    let plan = try SceneNumberWriter.plan(for: url)

    #expect(plan.changes.map(\.number) == ["1", "2"])
    #expect(plan.newText.contains("INT. CAFÉ “LA NIÑA” - DÍA #1#\n"))
    #expect(plan.newText.contains("EXT. PLAZA DE LA ESTACIÓN - NOCHE #2#\n"))
    let first = try #require(plan.changes.first)
    let prefix = Data("Title: Café Niña\n\nINT. CAFÉ “LA NIÑA” - DÍA".utf8)
    #expect(first.byteOffset == prefix.count)
    let onDisk = try Data(contentsOf: url)
    #expect(strippedBytes(plan) == onDisk)
  }

  @Test("A UTF-8 byte-order mark is kept")
  func byteOrderMarkIsKept() throws {
    let bom = Data([0xEF, 0xBB, 0xBF])
    let plan = try SceneNumberWriter.plan(
      for: try write(bom + Data(workshop().utf8), named: "bom.fountain"))

    #expect(plan.encoding == .utf8WithBOM)
    #expect(plan.newData.starts(with: bom))
    #expect(plan.changes.map(\.number) == ["1", "2"])
    #expect(plan.newData == bom + Data(plan.newText.utf8))
  }

  @Test("UTF-16 with a byte-order mark keeps its encoding")
  func utf16IsKept() throws {
    let bom: [UInt8] = [0xFF, 0xFE]
    let body = SceneNumberTextEncoding.utf16LittleEndian.encode(workshop())
    let plan = try SceneNumberWriter.plan(
      for: try write(Data(bom + body), named: "wide.fountain"))

    #expect(plan.encoding == .utf16LittleEndian)
    #expect(plan.changes.map(\.number) == ["1", "2"])
    #expect(plan.newData == SceneNumberTextEncoding.utf16LittleEndian.fileData(for: plan.newText))
  }

  @Test("A partly numbered file: existing numbers win, the rest take letters")
  func partlyNumberedGetsLetters() throws {
    let original =
      "Title: Lamps\n\nINT. WORKSHOP - DAY #4#\n\nMARA\nHand me that.\n\nEXT. YARD - NIGHT\n\nRain.\n"
    let plan = try SceneNumberWriter.plan(for: try write(original))

    #expect(plan.changes.map(\.number) == ["4A"])
    #expect(plan.changes.map(\.lineIndex) == [7])
    #expect(strippedBytes(plan) == plan.originalData)
  }

  @Test("A fully numbered file gives a plan with no changes")
  func fullyNumberedFileIsUnchanged() throws {
    let numbered =
      "Title: Lamps\n\nINT. WORKSHOP - DAY #1#\n\nMARA\nHand me that.\n\nEXT. YARD - NIGHT #2#\n"
    let plan = try SceneNumberWriter.plan(for: try write(numbered))

    #expect(plan.status == .planned)
    #expect(plan.changes.isEmpty)
    #expect(!plan.hasChanges)
    #expect(plan.newData == plan.originalData)

    // Re-planning a planned text changes nothing either.
    let first = try SceneNumberWriter.plan(for: try write(workshop()))
    let again = try SceneNumberWriter.plan(for: try write(first.newText))
    #expect(again.changes.isEmpty)
    #expect(again.newData == again.originalData)
  }

  @Test("A file that isn't .fountain is skipped")
  func nonFountainIsSkipped() throws {
    let url = try write(workshop(), named: "notes.txt")
    let plan = try SceneNumberWriter.plan(for: url)

    let skipped = plan.skipReason != nil
    #expect(skipped)
    #expect(plan.status == .skipped(reason: "not a .fountain file"))
    #expect(plan.changes.isEmpty)
    #expect(plan.newData.isEmpty)
    #expect(failedCheck(plan) == nil)
  }

  // MARK: - SN-5 on hand-corrupted plans

  @Test("Sanity: a real plan passes every check")
  func realPlanPasses() throws {
    let plan = try SceneNumberWriter.plan(for: try write(workshop()))
    #expect(failedCheck(plan) == nil)
  }

  @Test("(a) A plan that changes a byte outside the suffixes fails the suffix-strip check")
  func suffixStripFails() throws {
    let plan = try SceneNumberWriter.plan(for: try write(workshop()))
    let damagedText = plan.newText.replacingOccurrences(of: "Hand me that.", with: "Hand me this.")
    let damaged = SceneNumberPlan(
      file: plan.file, status: plan.status, encoding: plan.encoding,
      lineEnding: plan.lineEnding, originalData: plan.originalData,
      newData: Data(damagedText.utf8), originalText: plan.originalText, newText: damagedText,
      changes: plan.changes)

    #expect(failedCheck(damaged) == .suffixStrip)
  }

  @Test("(b) A plan that numbers a dialogue line fails the changed-lines check")
  func changedLinesFails() throws {
    let plan = try SceneNumberWriter.plan(for: try write(workshop()))
    let encoding = try #require(plan.encoding)
    let lineEnding = try #require(plan.lineEnding)
    var headings = SceneNumbering.numberedHeadings(in: plan.originalText).filter(\.needsNumber)
    // Line 5 is MARA's dialogue, not a slugline.
    headings.append(SceneHeading(lineIndex: 5, offset: 0, existingNumber: nil, assignedNumber: "9"))
    let damaged = SceneNumberWriter.build(
      file: plan.file, data: plan.originalData, encoding: encoding, text: plan.originalText,
      lineEnding: lineEnding, numbering: headings)

    #expect(damaged.newText.contains("Hand me that. #9#"))
    // The bytes still strip back to the original, so only (b) can catch it.
    #expect(strippedBytes(damaged) == damaged.originalData)
    #expect(failedCheck(damaged) == .changedLines)
  }

  @Test("(c) A plan that leaves a slugline unnumbered fails the parse check")
  func parseMismatchFails() throws {
    let plan = try SceneNumberWriter.plan(for: try write(workshop()))
    let encoding = try #require(plan.encoding)
    let lineEnding = try #require(plan.lineEnding)
    let all = SceneNumbering.numberedHeadings(in: plan.originalText).filter(\.needsNumber)
    let onlyFirst = Array(all.prefix(1))
    let damaged = SceneNumberWriter.build(
      file: plan.file, data: plan.originalData, encoding: encoding, text: plan.originalText,
      lineEnding: lineEnding, numbering: onlyFirst)

    #expect(damaged.changes.count == 1)
    // Every listed change is a valid slugline edit, so (a) and (b) pass.
    #expect(strippedBytes(damaged) == damaged.originalData)
    #expect(failedCheck(damaged) == .parseMismatch)
  }
}
