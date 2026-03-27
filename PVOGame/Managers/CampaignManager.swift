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
            name: "Первый контакт",
            subtitle: "5 волн — обучение",
            waveCount: 5,
            definition: LevelDefinition.campaignLevel1,
            requiredLevel: nil
        ),
        CampaignLevel(
            id: "night_shaheds",
            name: "Ночные Шахеды",
            subtitle: "8 волн — ночные атаки",
            waveCount: 8,
            definition: LevelDefinition.campaignLevel2,
            requiredLevel: "first_contact"
        ),
        CampaignLevel(
            id: "grad",
            name: "Град",
            subtitle: "10 волн — ракетный обстрел",
            waveCount: 10,
            definition: LevelDefinition.campaignLevel3,
            requiredLevel: "night_shaheds"
        ),
        CampaignLevel(
            id: "lancet_hunt",
            name: "Охота на Ланцеты",
            subtitle: "10 волн — защита башен",
            waveCount: 10,
            definition: LevelDefinition.campaignLevel4,
            requiredLevel: "grad"
        ),
        CampaignLevel(
            id: "iron_swarm",
            name: "Железный рой",
            subtitle: "12 волн — массовые FPV",
            waveCount: 12,
            definition: LevelDefinition.campaignLevel5,
            requiredLevel: "lancet_hunt"
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
