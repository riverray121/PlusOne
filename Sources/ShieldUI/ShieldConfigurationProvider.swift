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

    private func noUnlock(icon: String, title: String, subtitle: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.5),
            icon: UIImage(systemName: icon),
            title: .init(text: title, color: .white),
            subtitle: .init(text: subtitle, color: UIColor.white.withAlphaComponent(0.8)),
            primaryButtonLabel: .init(text: "Close", color: .white),
            primaryButtonBackgroundColor: UIColor.white.withAlphaComponent(0.2),
            secondaryButtonLabel: nil
        )
    }

    private func hardBlocked() -> ShieldConfiguration {
        noUnlock(
            icon: "nosign",
            title: "Hard blocked",
            subtitle: "You put this here for a reason. There is no unlock."
        )
    }

    private func outOfTime(_ rule: TimeLimitRule) -> ShieldConfiguration {
        noUnlock(
            icon: "hourglass",
            title: "Out of time",
            subtitle: "You've used your \(pluralMinutes(rule.minutes)) this \(rule.period.label). Back \(resetText(for: rule))."
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

    // nil means the item has an unlock path.
    private func lockedConfiguration(_ token: ApplicationToken?) -> ShieldConfiguration? {
        guard let token else { return nil }
        if SharedStore.shared.hardSelection.applicationTokens.contains(token) { return hardBlocked() }
        if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        return nil
    }

    private func lockedConfiguration(_ token: WebDomainToken?) -> ShieldConfiguration? {
        guard let token else { return nil }
        if SharedStore.shared.hardSelection.webDomainTokens.contains(token) { return hardBlocked() }
        if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        return nil
    }

    private func lockedConfiguration(_ token: ActivityCategoryToken?) -> ShieldConfiguration? {
        guard let token else { return nil }
        if SharedStore.shared.hardSelection.categoryTokens.contains(token) { return hardBlocked() }
        if let rule = TimeLimitManager.shared.exhaustedRule(containing: token) { return outOfTime(rule) }
        return nil
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        lockedConfiguration(application.token) ?? unlockable()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        lockedConfiguration(application.token)
            ?? lockedConfiguration(category.token)
            ?? unlockable()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        lockedConfiguration(webDomain.token) ?? unlockable()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        lockedConfiguration(webDomain.token)
            ?? lockedConfiguration(category.token)
            ?? unlockable()
    }
}
