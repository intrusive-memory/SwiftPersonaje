import Foundation
import SwiftReparto

/// A character's tier as the evidence reports it (VE-6, UD19): `major` or
/// `minor`. The tier is reported only; nothing here writes it to `CAST.md`.
public enum CharacterTier: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
  case major
  case minor

  /// A member is major when they speak in at least this percentage of all
  /// dialogue blocks.
  public static let blockPercentThreshold = 8
  /// A member is major when they appear in at least this percentage of scenes.
  public static let scenePercentThreshold = 15

  /// The tier for the given counts.
  ///
  /// An existing `CAST.md` `role` wins: a major role (`lead`, `supporting`,
  /// `guest`, `narrator`; SwiftReparto's `CastRole.isMajor`) reports major,
  /// any other role reports minor. Without a role, a member is major when
  /// they have at least 8% of all dialogue blocks or appear in at least 15%
  /// of scenes. Both comparisons are exact integer arithmetic
  /// (`blocks * 100 >= total * 8`), so the boundaries don't depend on
  /// floating point. A member with no blocks and no scenes is minor.
  ///
  /// - Parameters:
  ///   - memberBlocks: The member's dialogue blocks, counted as
  ///     `CastDiscovery` counts `lineCount` (one per cue).
  ///   - totalBlocks: Every dialogue block in the project.
  ///   - memberScenes: Scenes (the scene rule: slugline-started) in which
  ///     the member speaks.
  ///   - totalScenes: Every scene in the project.
  ///   - castRole: The member's `role` in `CAST.md`, if any.
  public static func tier(
    memberBlocks: Int, totalBlocks: Int, memberScenes: Int, totalScenes: Int,
    castRole: CastRole? = nil
  ) -> CharacterTier {
    if let castRole { return castRole.isMajor ? .major : .minor }
    let manyBlocks =
      memberBlocks > 0 && memberBlocks * 100 >= totalBlocks * blockPercentThreshold
    let manyScenes =
      memberScenes > 0 && memberScenes * 100 >= totalScenes * scenePercentThreshold
    return (manyBlocks || manyScenes) ? .major : .minor
  }
}

/// The counts a tier is computed from, for one member of a project.
public struct CharacterTierCounts: Sendable, Equatable, Hashable, Codable {
  public let memberBlocks: Int
  public let totalBlocks: Int
  public let memberScenes: Int
  public let totalScenes: Int

  public init(memberBlocks: Int, totalBlocks: Int, memberScenes: Int, totalScenes: Int) {
    self.memberBlocks = memberBlocks
    self.totalBlocks = totalBlocks
    self.memberScenes = memberScenes
    self.totalScenes = totalScenes
  }

  /// The computed tier for these counts (see
  /// ``CharacterTier/tier(memberBlocks:totalBlocks:memberScenes:totalScenes:castRole:)``).
  public func tier(castRole: CastRole? = nil) -> CharacterTier {
    CharacterTier.tier(
      memberBlocks: memberBlocks, totalBlocks: totalBlocks, memberScenes: memberScenes,
      totalScenes: totalScenes, castRole: castRole)
  }
}

extension EvidenceCorpus {

  /// The number of scenes in the project under the scene rule: the headings
  /// SN-1 finds, summed over every episode. A forced `.` line is not one.
  public var sceneCount: Int { episodes.reduce(0) { $0 + $1.headings.count } }

  /// The number of dialogue blocks in the project: every cue, as
  /// `CastDiscovery` counts `lineCount`.
  public var dialogueBlockCount: Int {
    episodes.reduce(0) { total, episode in
      total + episode.blocks.filter { $0.isDialogue && $0.cue != nil }.count
    }
  }

  /// The tier counts for `member` (a `character`, or any cue of theirs).
  public func tierCounts(for member: String) -> CharacterTierCounts {
    let name = EvidenceCue.speaker(of: member)
    var blocks = 0
    var scenes = Set<String>()
    for episode in episodes {
      for block in episode.blocks where block.isDialogue && block.cue != nil && block.speaker == name {
        blocks += 1
        if block.scene >= 0 { scenes.insert("\(episode.name)#\(block.scene)") }
      }
    }
    return CharacterTierCounts(
      memberBlocks: blocks, totalBlocks: dialogueBlockCount, memberScenes: scenes.count,
      totalScenes: sceneCount)
  }
}

extension CharacterEvidence {

  /// The counts this member's tier is computed from, within `corpus`.
  public func tierCounts(in corpus: EvidenceCorpus) -> CharacterTierCounts {
    corpus.tierCounts(for: member)
  }

  /// The member's tier (VE-6): their `CAST.md` `role` when `castRole` is
  /// given, otherwise computed from `corpus`. Reported only, never written.
  public func tier(in corpus: EvidenceCorpus, castRole: CastRole? = nil) -> CharacterTier {
    tierCounts(in: corpus).tier(castRole: castRole)
  }
}
