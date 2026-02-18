import Foundation
import CoreGraphics

// MARK: - Perk Definitions

enum Perk: CaseIterable {
    // Temporary (duration-based)
    case thicc          // PiP grows 1.8x — 12s
    case slowmo         // Paddle speed ×0.4 — 8s
    case freeze         // Paddle frozen — 2.5s
    case drunk          // Paddle dodge target wobbles — 10s
    case ghost          // Paddle dodges blind — 6s
    case earthquake     // Paddle jitters ±8px — 8s

    // Permanent (stackable)
    case homing         // Velocity nudges toward paddle 2.5%/stack
    case gravityWell    // Pull force near paddle 40px/s/stack
    case shrinkRay      // Paddle 20% shorter per stack (multiplicative)
    case multiHit       // Each hit = 1+stacks score
    case ricochet       // Wall bounces add ±20°/stack random deviation
    case steelFist      // Hit cooldown reduced per stack

    var isTemporary: Bool {
        switch self {
        case .thicc, .slowmo, .freeze, .drunk, .ghost, .earthquake: return true
        default: return false
        }
    }

    var duration: CGFloat {
        switch self {
        case .thicc: return 8
        case .slowmo: return 8
        case .freeze: return 2.5
        case .drunk: return 10
        case .ghost: return 4
        case .earthquake: return 8
        default: return 0
        }
    }

    var name: String {
        switch self {
        case .thicc: return "THICC"
        case .slowmo: return "SLOWMO"
        case .freeze: return "FREEZE"
        case .drunk: return "DRUNK"
        case .ghost: return "GHOST"
        case .earthquake: return "QUAKE"
        case .homing: return "HOMING"
        case .gravityWell: return "GRAVITY"
        case .shrinkRay: return "SHRINK"
        case .multiHit: return "MULTI"
        case .ricochet: return "RICOCHET"
        case .steelFist: return "STEEL"
        }
    }

    var desc: String {
        switch self {
        case .thicc: return "PiP grows 1.8x"
        case .slowmo: return "Paddle ×0.4 speed"
        case .freeze: return "Paddle frozen"
        case .drunk: return "Paddle wobbles"
        case .ghost: return "Paddle blind"
        case .earthquake: return "Paddle jitters"
        case .homing: return "Ball seeks paddle"
        case .gravityWell: return "Pull near paddle"
        case .shrinkRay: return "Paddle shrinks"
        case .multiHit: return "Multi-score hits"
        case .ricochet: return "Chaotic bounces"
        case .steelFist: return "Faster hits"
        }
    }
}

// MARK: - Perk State Machine

class PerkState {
    var realHits = 0
    var lastPerkAtHit = 0
    var paddleLevel = 0

    // Active temporary perks: perk → remaining seconds
    var activeTemporary: [Perk: CGFloat] = [:]

    // Permanent perk stack counts
    var permanentStacks: [Perk: Int] = [:]

    let perksPerThreshold = 5

    func isActive(_ perk: Perk) -> Bool {
        if perk.isTemporary {
            return (activeTemporary[perk] ?? 0) > 0
        } else {
            return (permanentStacks[perk] ?? 0) > 0
        }
    }

    func stacks(_ perk: Perk) -> Int {
        if perk.isTemporary {
            return (activeTemporary[perk] ?? 0) > 0 ? 1 : 0
        }
        return permanentStacks[perk] ?? 0
    }

    func tickTimers(dt: CGFloat) {
        for (perk, remaining) in activeTemporary {
            let newVal = remaining - dt
            if newVal <= 0 {
                activeTemporary.removeValue(forKey: perk)
            } else {
                activeTemporary[perk] = newVal
            }
        }
    }

    func shouldOfferPerk() -> Bool {
        return realHits >= lastPerkAtHit + perksPerThreshold && realHits > 0
    }

    func registerHit() {
        realHits += 1
    }

    func pickPerk(_ perk: Perk) {
        lastPerkAtHit = realHits
        paddleLevel += 1

        if perk.isTemporary {
            activeTemporary[perk] = perk.duration
        } else {
            permanentStacks[perk, default: 0] += 1
        }
    }

    func randomOffering() -> [Perk] {
        let all = Perk.allCases.shuffled()
        return Array(all.prefix(3))
    }

    func reset() {
        realHits = 0
        lastPerkAtHit = 0
        paddleLevel = 0
        activeTemporary.removeAll()
        permanentStacks.removeAll()
    }

    // MARK: - Paddle Level Scaling

    var paddleSpeedBonus: CGFloat {
        return min(CGFloat(paddleLevel) * 0.015, 0.55) // added to base, cap contribution
    }

    var reactionDelayReduction: CGFloat {
        return min(CGFloat(paddleLevel) * 0.015, 0.30) // seconds reduced
    }

    var dodgeInaccuracyReduction: CGFloat {
        return min(CGFloat(paddleLevel) * 0.004, 0.135)
    }

    var panicChanceReduction: CGFloat {
        return min(CGFloat(paddleLevel) * 0.03, 0.47)
    }

    // MARK: - Perk Effect Helpers

    var hitCooldownSeconds: Double {
        let s = stacks(.steelFist)
        if s == 0 { return 0.5 }
        return max(0.1, 0.5 - 0.15 * Double(s))
    }

    var scorePerHit: Int {
        return 1 + stacks(.multiHit)
    }

    var paddleLengthMultiplier: CGFloat {
        let s = stacks(.shrinkRay)
        if s == 0 { return 1.0 }
        return pow(0.8, CGFloat(s))
    }

    var homingStrength: CGFloat {
        return CGFloat(stacks(.homing)) * 0.025
    }

    var gravityWellStrength: CGFloat {
        return CGFloat(stacks(.gravityWell)) * 40.0
    }

    var ricochetAngle: CGFloat {
        return CGFloat(stacks(.ricochet)) * 20.0 * .pi / 180.0
    }
}
