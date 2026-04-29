//
//  CampaignManager.swift
//  PVOGame
//
//  Campaign progress: tracks which levels are completed and star ratings.
//  Persists via UserDefaults.
//

import Foundation

struct CampaignLevel {
    let id: String
    let name: String
    let subtitle: String
    let waveCount: Int
    let definition: LevelDefinition

    /// Minimum level ID that must be completed to unlock this level
    let requiredLevel: String?
}

class CampaignManager {

    static let shared = CampaignManager()

    private let starsKey = "campaign_stars"  // [levelId: stars]
    private let completedKey = "campaign_completed"  // [levelId]

    // MARK: - Campaign Levels

    let levels: [CampaignLevel] = [
        CampaignLevel(
            id: "first_contact",
            name: "First Contact",
            subtitle: "4 waves — tutorial",
            waveCount: 4,
            definition: LevelDefinition.campaignLevel1,
            requiredLevel: nil
        ),
        CampaignLevel(
            id: "night_alarm",
            name: "Night Alarm",
            subtitle: "5 waves — night attacks",
            waveCount: 5,
            definition: LevelDefinition.campaignLevel2,
            requiredLevel: "first_contact"
        ),
        CampaignLevel(
            id: "missile_strike",
            name: "Missile Strike",
            subtitle: "5 waves — missile barrage",
            waveCount: 5,
            definition: LevelDefinition.campaignLevel3,
            requiredLevel: "night_alarm"
        ),
        CampaignLevel(
            id: "peoples_defense",
            name: "People's Defense",
            subtitle: "5 waves — mass attacks",
            waveCount: 5,
            definition: LevelDefinition.campaignLevel4,
            requiredLevel: "missile_strike"
        ),
        CampaignLevel(
            id: "city_defense",
            name: "City Defense",
            subtitle: "6 waves — settlements",
            waveCount: 6,
            definition: LevelDefinition.campaignLevel5,
            requiredLevel: "peoples_defense"
        ),
        CampaignLevel(
            id: "fpv_attack",
            name: "FPV Attack",
            subtitle: "6 waves — EW & FPV",
            waveCount: 6,
            definition: LevelDefinition.campaignLevel6,
            requiredLevel: "city_defense"
        ),
        CampaignLevel(
            id: "grad",
            name: "Hail",
            subtitle: "7 waves — heavy missiles",
            waveCount: 7,
            definition: LevelDefinition.campaignLevel7,
            requiredLevel: "fpv_attack"
        ),
        CampaignLevel(
            id: "cruise_missiles",
            name: "Cruise Missiles",
            subtitle: "7 waves — cruise missiles",
            waveCount: 7,
            definition: LevelDefinition.campaignLevel8,
            requiredLevel: "grad"
        ),
        CampaignLevel(
            id: "lancets",
            name: "Lancets",
            subtitle: "8 waves — loitering munitions",
            waveCount: 8,
            definition: LevelDefinition.campaignLevel9,
            requiredLevel: "cruise_missiles"
        ),
        CampaignLevel(
            id: "iron_swarm",
            name: "Iron Swarm",
            subtitle: "10 waves — all combined",
            waveCount: 10,
            definition: LevelDefinition.campaignLevel10,
            requiredLevel: "lancets"
        ),
        CampaignLevel(
            id: "iranian_night",
            name: "Iranian Night",
            subtitle: "5 waves — combo finale",
            waveCount: 5,
            definition: LevelDefinition.campaignLevel11,
            requiredLevel: "iron_swarm"
        ),
        CampaignLevel(
            id: "test_heavy",
            name: "TEST: Combo Showcase",
            subtitle: "2 waves — mine field + boss",
            waveCount: 2,
            definition: LevelDefinition.testHeavyDrones,
            requiredLevel: nil
        ),
        CampaignLevel(
            id: "test_explosions",
            name: "TEST: Explosions",
            subtitle: "4 waves — shahed swarms",
            waveCount: 4,
            definition: LevelDefinition.testExplosions,
            requiredLevel: nil
        ),
        CampaignLevel(
            id: "test_ew",
            name: "TEST: Heavy Drone",
            subtitle: "3 waves — Bayraktar-style strikes",
            waveCount: 3,
            definition: LevelDefinition.testEWDrone,
            requiredLevel: nil
        ),
    ]

    // MARK: - Progress

    func isUnlocked(_ levelId: String) -> Bool {
        guard let level = levels.first(where: { $0.id == levelId }) else { return false }
        guard let req = level.requiredLevel else { return true }
        return isCompleted(req)
    }

    func isCompleted(_ levelId: String) -> Bool {
        let completed = UserDefaults.standard.stringArray(forKey: completedKey) ?? []
        return completed.contains(levelId)
    }

    func stars(for levelId: String) -> Int {
        let dict = UserDefaults.standard.dictionary(forKey: starsKey) as? [String: Int] ?? [:]
        return dict[levelId] ?? 0
    }

    func totalStars() -> Int {
        let dict = UserDefaults.standard.dictionary(forKey: starsKey) as? [String: Int] ?? [:]
        return dict.values.reduce(0, +)
    }

    /// Calculate stars based on remaining HQ HP. Call when a campaign level is won.
    func completeLevel(_ levelId: String, remainingHP: Int, maxHP: Int) {
        // Mark completed
        var completed = UserDefaults.standard.stringArray(forKey: completedKey) ?? []
        if !completed.contains(levelId) {
            completed.append(levelId)
            UserDefaults.standard.set(completed, forKey: completedKey)
        }

        // Calculate stars (1-3)
        let ratio = CGFloat(remainingHP) / CGFloat(maxHP)
        let newStars: Int
        if ratio >= 0.8 { newStars = 3 }
        else if ratio >= 0.4 { newStars = 2 }
        else { newStars = 1 }

        // Only upgrade, never downgrade
        var dict = UserDefaults.standard.dictionary(forKey: starsKey) as? [String: Int] ?? [:]
        let existing = dict[levelId] ?? 0
        if newStars > existing {
            dict[levelId] = newStars
            UserDefaults.standard.set(dict, forKey: starsKey)
        }
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: starsKey)
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
