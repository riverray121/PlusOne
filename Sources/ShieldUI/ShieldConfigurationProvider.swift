import ManagedSettings
import ManagedSettingsUI
import UIKit

// Renders the block screen shown over shielded apps and websites. Hard-blocked
// items and spent time limits get variants with no unlock path.
class ShieldConfigurationProvider: ShieldConfigurationDataSource {

    private func unlockable() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.4),
            icon: UIImage(systemName: "person.2.fill"),
            title: .init(text: "Blocked by PlusOne", color: .white),
            subtitle: .init(
                text: "Take a selfie with someone to unlock \(pluralMinutes(SharedStore.shared.durationMinutes)).",
                color: UIColor.white.withAlphaComponent(0.8)
            ),
            primaryButtonLabel: .init(text: "Unlock with a selfie", color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: nil
        )
    }

    private func hardBlocked() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.5),
            icon: UIImage(systemName: "nosign"),
            title: .init(text: "Hard blocked", color: .white),
            subtitle: .init(
                text: "You put this here for a reason. There is no unlock.",
                color: UIColor.white.withAlphaComponent(0.8)
            ),
            primaryButtonLabel: .init(text: "Close", color: .white),
            primaryButtonBackgroundColor: UIColor.white.withAlphaComponent(0.2),
            secondaryButtonLabel: nil
        )
    }

    private func outOfTime(_ rule: TimeLimitRule) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.5),
            icon: UIImage(systemName: "hourglass"),
            title: .init(text: "Out of time", color: .white),
            subtitle: .init(
                text: "You've used your \(pluralMinutes(rule.minutes)) this \(rule.period.label). Back \(resetText(for: rule)).",
                color: UIColor.white.withAlphaComponent(0.8)
            ),
            primaryButtonLabel: .init(text: "Close", color: .white),
            primaryButtonBackgroundColor: UIColor.white.withAlphaComponent(0.2),
            secondaryButtonLabel: nil
        )
    }

    private func resetText(for rule: TimeLimitRule) -> String {
        switch rule.period {
        case .day:
            return "at midnight"
        case .hour:
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "at \(formatter.string(from: rule.nextReset()))"
        }
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        if let token = application.token {
            if SharedStore.shared.hardSelection.applicationTokens.contains(token) {
                return hardBlocked()
            }
            if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) {
                return outOfTime(rule)
            }
        }
        return unlockable()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let hard = SharedStore.shared.hardSelection
        if let token = application.token {
            if hard.applicationTokens.contains(token) { return hardBlocked() }
            if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        }
        if let token = category.token {
            if hard.categoryTokens.contains(token) { return hardBlocked() }
            if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        }
        return unlockable()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        if let token = webDomain.token {
            if SharedStore.shared.hardSelection.webDomainTokens.contains(token) {
                return hardBlocked()
            }
            if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) {
                return outOfTime(rule)
            }
        }
        return unlockable()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let hard = SharedStore.shared.hardSelection
        if let token = webDomain.token {
            if hard.webDomainTokens.contains(token) { return hardBlocked() }
            if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        }
        if let token = category.token {
            if hard.categoryTokens.contains(token) { return hardBlocked() }
            if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        }
        return unlockable()
    }
}
