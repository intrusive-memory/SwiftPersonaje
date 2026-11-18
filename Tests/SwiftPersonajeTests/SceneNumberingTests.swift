import Foundation
import Testing

@testable import SwiftPersonaje

/// SN-1 and SN-2: the scene rule and in-memory numbering. Synthetic text only.
@Suite("Scene headings and numbers (SN-1, SN-2)")
struct SceneNumberingTests {

  /// The SN-1 number of every heading in `text`, in order.
  private func numbers(_ text: String) -> [String?] {
    SceneNumbering.numberedHeadings(in: text).map(\.assignedNumber)
  }

  // MARK: - SN-1

  @Test("No numbers anywhere: 1, 2, 3")
  func noNumbersCountsFromOne() {
    let text = "INT. BAKERY - DAY\n\nHello.\n\nEXT. HARBOR - NIGHT\n\nINT. ATTIC - DAY\n"
    let headings = SceneNumbering.numberedHeadings(in: text)
    #expect(headings.map(\.existingNumber) == [nil, nil, nil])
    #expect(headings.map(\.assignedNumber) == ["1", "2", "3"])
    let allNeedNumbers = headings.allSatisfy { $0.needsNumber }
    #expect(allNeedNumbers)
  }

  @Test("All numbered: every number kept, nothing to write")
  func allNumberedAreKept() {
    let text = "INT. BAKERY #1#\n\nEXT. HARBOR #2#\n\nINT. ATTIC #7#\n"
    let headings = SceneNumbering.numberedHeadings(in: text)
    #expect(headings.map(\.existingNumber) == ["1", "2", "7"])
    #expect(headings.map(\.assignedNumber) == ["1", "2", "7"])
    let anyNeedsNumber = headings.contains { $0.needsNumber }
    #expect(!anyNeedsNumber)
  }

  @Test("Mixed 12, 12A, 13: gaps take the previous number plus a letter")
  func lettersAfterExistingNumber() {
    let text = """
      INT. BAKERY - DAY #12#

      EXT. HARBOR - NIGHT

      INT. ATTIC - DAY #12A#

      EXT. PIER - DAY

      INT. CELLAR - NIGHT #13#

      EXT. ROOFTOP
      """
    // After #12#, 12A is taken further down, so the gap takes 12B. After
    // #12A#, 12B is now taken too, so the next gap takes 12C.
    #expect(numbers(text) == ["12", "12B", "12A", "12C", "13", "13A"])
    let all = numbers(text).compactMap { $0 }
    #expect(Set(all).count == all.count)
  }

  @Test("Gaps between 12 and 13 get 12A, 12B")
  func gapsGetSuccessiveLetters() {
    let text = "INT. A - DAY #12#\n\nEXT. B\n\nINT. C\n\nINT. D #13#\n\nEXT. E\n"
    #expect(numbers(text) == ["12", "12A", "12B", "13", "13A"])
  }

  @Test("Unnumbered headings before the first number take 0A, 0B")
  func beforeFirstNumberTakesZero() {
    let text = "INT. BAKERY\n\nEXT. HARBOR\n\nINT. ATTIC #5#\n\nEXT. PIER\n"
    #expect(numbers(text) == ["0A", "0B", "5", "5A"])
  }

  @Test("A new letter skips a number already used (12A exists)")
  func letterSkipsExistingNumber() {
    let text = "INT. BAKERY #12#\n\nEXT. HARBOR\n\nINT. ATTIC #12A#\n"
    #expect(numbers(text) == ["12", "12B", "12A"])
  }

  @Test("A repeated number is kept on both headings")
  func repeatedNumberIsKept() {
    let text = "INT. A #3#\n\nEXT. B #3#\n\nINT. C\n"
    #expect(numbers(text) == ["3", "3", "3A"])
  }

  @Test("Letters run A…Z, then AA")
  func lettersRollOver() {
    #expect(SceneNumbering.letterSuffix(0) == "A")
    #expect(SceneNumbering.letterSuffix(25) == "Z")
    #expect(SceneNumbering.letterSuffix(26) == "AA")
    #expect(SceneNumbering.letterSuffix(27) == "AB")
    #expect(SceneNumbering.letterIndex("") == 0)
    #expect(SceneNumbering.letterIndex("A") == 1)
    #expect(SceneNumbering.letterIndex("AA") == 27)

    var lines = ["INT. START #4#"]
    for index in 0..<27 { lines.append("EXT. PLACE \(index)") }
    let assigned = numbers(lines.joined(separator: "\n\n"))
    #expect(assigned[1] == "4A")
    #expect(assigned[26] == "4Z")
    #expect(assigned[27] == "4AA")
  }

  // MARK: - The scene rule

  @Test("Forced lines never start a scene")
  func forcedLinesAreNotScenes() {
    let text = """
      INT. BAKERY - DAY

      .MUSIC CONTINUES

      MARGOT
      Is it done?

      .THE ROOM

      EXT. HARBOR - NIGHT
      """
    let headings = SceneNumbering.numberedHeadings(in: text)
    #expect(headings.map(\.lineIndex) == [0, 9])
    #expect(headings.map(\.assignedNumber) == ["1", "2"])
    // A forced line belongs to the scene before it.
    #expect(SceneNumbering.numberForScene(atLine: 2, in: headings) == "1")
    #expect(SceneNumbering.numberForScene(atLine: 7, in: headings) == "1")
  }

  @Test("Sluglines inside [[ ]] notes and /* */ boneyard are skipped")
  func notesAndBoneyardAreSkipped() {
    let text = """
      INT. BAKERY - DAY

      [[
      INT. NOT A SCENE - DAY
      ]]

      /*
      EXT. CUT SCENE - NIGHT

      INT. ALSO CUT - DAY
      */

      EXT. HARBOR - NIGHT
      """
    let headings = SceneNumbering.numberedHeadings(in: text)
    #expect(headings.map(\.lineIndex) == [0, 12])
    #expect(headings.map(\.assignedNumber) == ["1", "2"])
  }

  @Test("An unclosed [[ or /* is plain text and hides nothing")
  func unclosedOpenersHideNothing() {
    let text = "INT. BAKERY\n\n[[ a stray opener\n\nEXT. HARBOR\n\n/* another\n\nINT. ATTIC\n"
    #expect(numbers(text) == ["1", "2", "3"])
  }

  @Test("INT./EXT. and EST. are sluglines; other look-alikes are not")
  func intExtAndEstAreSluglines() {
    let text = """
      INT./EXT. CAR - MOVING

      EST. LIGHTHOUSE - DAWN

      INTERIOR DESIGN

      EXT.HARBOR

      int. lowercase

      INT.
      """
    let headings = SceneNumbering.numberedHeadings(in: text)
    #expect(headings.map(\.lineIndex) == [0, 2])
    #expect(headings.map(\.assignedNumber) == ["1", "2"])
    #expect(SceneNumbering.isSlugline("INT./EXT. CAR"))
    #expect(SceneNumbering.isSlugline("EST.\tTOWER"))
    #expect(!SceneNumbering.isSlugline("INT./EXT.CAR"))
    #expect(!SceneNumbering.isSlugline(".INT. FORCED"))
  }

  @Test("Trailing spaces: a heading still counts, and its #n# is still read")
  func trailingSpaces() {
    let text = "INT. BAKERY - DAY   \n\nEXT. HARBOR - NIGHT #4#   \n\nINT. ATTIC\t\n"
    let headings = SceneNumbering.numberedHeadings(in: text)
    #expect(headings.map(\.existingNumber) == [nil, "4", nil])
    #expect(headings.map(\.assignedNumber) == ["0A", "4", "4A"])
  }

  @Test("A # with no space before it is not a scene number")
  func numberNeedsLeadingSpace() {
    let headings = SceneNumbering.headings(in: "INT. ROOM#4#\n\nEXT. YARD #5#\n")
    #expect(headings.map(\.existingNumber) == [nil, "5"])
  }

  @Test("CRLF text has the same lines and numbers as LF text")
  func crlfMatchesLF() {
    let lf = "INT. A\nHi.\nEXT. B #2#\n"
    let crlf = "INT. A\r\nHi.\r\nEXT. B #2#\r\n"
    #expect(SceneNumbering.headings(in: lf).map(\.lineIndex) == [0, 2])
    #expect(SceneNumbering.headings(in: crlf).map(\.lineIndex) == [0, 2])
    #expect(numbers(crlf) == ["0A", "2"])
    #expect(SceneNumbering.headings(in: crlf)[1].offset == 13)
  }

  // MARK: - SN-2 lookup

  @Test("Lookup by position gives the scene's number without writing")
  func numberForSceneByOffset() throws {
    let text =
      "Title text before.\n\nINT. BAKERY - DAY\n\nMARGOT\nHello.\n\nEXT. HARBOR #9#\n\nOSWIN\nBye.\n"
    let headings = SceneNumbering.numberedHeadings(in: text)
    let hello = try #require(text.range(of: "Hello.")).lowerBound.utf16Offset(in: text)
    let bye = try #require(text.range(of: "Bye.")).lowerBound.utf16Offset(in: text)
    #expect(SceneNumbering.numberForScene(at: 0, in: headings) == nil)
    #expect(SceneNumbering.numberForScene(at: hello, in: headings) == "0A")
    #expect(SceneNumbering.numberForScene(at: bye, in: headings) == "9")
    #expect(SceneNumbering.numberForScene(at: headings[1].offset, in: headings) == "9")
    #expect(SceneNumbering.numberForScene(at: bye, inText: text) == "9")
    #expect(SceneNumbering.numberForScene(atLine: 4, in: headings) == "0A")
  }

  @Test("Headings report line index, offset and the existing number")
  func headingFields() {
    let text = "INT. A\n\nEXT. B #3#\n"
    let headings = SceneNumbering.headings(in: text)
    #expect(
      headings == [
        SceneHeading(lineIndex: 0, offset: 0, existingNumber: nil),
        SceneHeading(lineIndex: 2, offset: 8, existingNumber: "3"),
      ])
    let noneAssigned = headings.allSatisfy { $0.assignedNumber == nil }
    #expect(noneAssigned)
  }
}
