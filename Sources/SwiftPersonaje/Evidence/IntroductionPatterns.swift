import Foundation

/// One rule for reading an action line about a character (VE-2, VE-4).
///
/// A pattern is an ICU regular expression matched case-insensitively against
/// the action paragraph's text. The ``Category`` says what a match means:
/// a description of the character (age, ethnicity, build, voice), which makes
/// a later line naming them an introduction (VE-2), or a reference to a group
/// that names no one (VE-4).
struct IntroductionPattern: Sendable, Equatable {

  /// What a match tells us.
  enum Category: String, Sendable, Equatable, CaseIterable {
    /// An age: `40's`, `of about twelve`, `sixty years old`, `late thirties`.
    case age
    /// An ethnicity: `BLACK`, `South Asian`, `Latina`.
    case ethnicity
    /// A build or height: `wiry`, `stocky`, `six-foot-five`.
    case build
    /// A description of the voice: `speaks with a clipped accent`, `gravelly`.
    case voice
    /// A group named by no one's name: `They each…`, `All of them…` (VE-4).
    case groupReference
  }

  /// What a match means.
  let category: Category
  /// A short name for the pattern, for diagnostics and tests.
  let name: String
  /// The ICU regular expression, matched case-insensitively.
  let regex: String

  /// `true` when `text` matches this pattern.
  func matches(_ text: String) -> Bool {
    text.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
  }
}

/// The table of action-line patterns (VE-2, VE-4). Every pattern the evidence
/// reader uses is here, each with its own doc comment; ``all`` lists them.
///
/// The patterns are deliberately simple word lists. They only decide whether
/// a *later* action line that already names the character in capitals is
/// also an introduction, or whether a line that names no one speaks of a
/// group, so a false positive costs one extra evidence item, never a wrong
/// name.
enum IntroductionPatterns {

  // MARK: Number words

  /// Ages written in digits or in words, up to ninety-nine.
  private static let number =
    #"(?:\d{1,3}|(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:-(?:one|two|three|four|five|six|seven|eight|nine))?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)"#

  /// Small numbers for heights.
  private static let small =
    #"(?:\d|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#

  // MARK: Age

  /// A decade, the screenplay convention: `40's`, `20s`, `60's`.
  static let decadeAge = IntroductionPattern(
    category: .age, name: "decade age", regex: #"\b\d0['’]?s\b"#)

  /// An approximate or stated age: `of about twelve`, `aged 30`, `age forty`.
  static let approximateAge = IntroductionPattern(
    category: .age, name: "approximate age",
    regex: #"(?:\bof\s+(?:about|around|roughly|nearly|almost)\s+|\baged?\s+)"# + number + #"\b"#)

  /// An age in years: `sixty years old`, `twelve-year-old`.
  static let yearsOld = IntroductionPattern(
    category: .age, name: "years old", regex: #"\b"# + number + #"[-\s]years?[-\s]old\b"#)

  /// A stage of life: `late thirties`, `mid-40s`, `teenage`, `middle-aged`,
  /// `elderly`.
  static let lifeStage = IntroductionPattern(
    category: .age, name: "life stage",
    regex:
      #"\b(?:(?:early|mid|late)[-\s]?(?:teens|twenties|thirties|forties|fifties|sixties|seventies|eighties|nineties|\d0['’]?s)|teenaged?|teenager|middle-aged|elderly)\b"#
  )

  // MARK: Ethnicity

  /// An ethnicity named in the description: `BLACK`, `White`, `South Asian`,
  /// `Latina`. Words like `white` also describe hair or clothes; on a line
  /// that already names the character that only adds one item.
  static let ethnicity = IntroductionPattern(
    category: .ethnicity, name: "ethnicity",
    regex:
      #"\b(?:black|white|asian|east\s+asian|south\s+asian|southeast\s+asian|latina|latino|latinx|hispanic|mixed-race|biracial|indigenous|native\s+american|middle\s+eastern|arab|caucasian|african|caribbean|pacific\s+islander|maori|polynesian|romani)\b"#
  )

  // MARK: Build

  /// A build: `wiry`, `stocky`, `lanky`, `heavyset`, `broad-shouldered`.
  static let build = IntroductionPattern(
    category: .build, name: "build",
    regex:
      #"\b(?:tall|short|stocky|wiry|lanky|slight|slender|thin|skinny|heavy-?set|burly|broad-shouldered|barrel-chested|pot-bellied|stout|portly|muscular|petite|gangly|willowy|hulking|rotund|plump|lean|brawny|frail)\b"#
  )

  /// A height: `six-foot-five`, `5-foot`, `6'2"`.
  static let height = IntroductionPattern(
    category: .build, name: "height",
    regex: #"(?:\b"# + small + #"[-\s]f(?:oo|ee)t(?:[-\s]"# + small
      + #")?\b|\b\d['’]\s?\d{1,2}["”])"#)

  // MARK: Voice

  /// A description of the voice: `speaks with…`, `accent`, `drawl`,
  /// `gravelly`, `baritone`, `stammers`.
  static let voice = IntroductionPattern(
    category: .voice, name: "voice",
    regex:
      #"\b(?:voices?|voiced|speaks?|speaking|accents?|accented|drawl|drawls|brogue|lisp|lisps|lilt|twang|husky|gravelly|raspy|hoarse|baritone|tenor|alto|soprano|falsetto|stammers?|stutters?|mumbles?|whispery|nasal|booming)\b"#
  )

  // MARK: Group references (VE-4)

  /// A plural pronoun with a quantifier: `They each…`, `They all…`,
  /// `They both…`.
  static let theyEach = IntroductionPattern(
    category: .groupReference, name: "they each", regex: #"\bthey\s+(?:each|all|both)\b"#)

  /// A quantifier over "them": `Each of them…`, `All of them…`,
  /// `Both of them…`, `Every one of them…`.
  static let eachOfThem = IntroductionPattern(
    category: .groupReference, name: "each of them",
    regex: #"\b(?:each|all|both|every\s+one|none)\s+of\s+them\b"#)

  // MARK: The table

  /// Every pattern, in the order above.
  static let all: [IntroductionPattern] = [
    decadeAge, approximateAge, yearsOld, lifeStage,
    ethnicity,
    build, height,
    voice,
    theyEach, eachOfThem,
  ]

  /// The categories a line matches, in table order, without repeats.
  static func categories(matching text: String) -> [IntroductionPattern.Category] {
    var result: [IntroductionPattern.Category] = []
    for pattern in all where !result.contains(pattern.category) && pattern.matches(text) {
      result.append(pattern.category)
    }
    return result
  }

  /// `true` when `text` gives an age, an ethnicity, a build or a voice (VE-2).
  static func describesCharacter(_ text: String) -> Bool {
    all.contains { $0.category != .groupReference && $0.matches(text) }
  }

  /// `true` when `text` speaks of a group without naming it (VE-4).
  static func refersToGroup(_ text: String) -> Bool {
    all.contains { $0.category == .groupReference && $0.matches(text) }
  }
}
