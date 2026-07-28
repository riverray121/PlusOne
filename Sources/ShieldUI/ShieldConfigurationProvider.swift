import ManagedSettings
import ManagedSettingsUI
import UIKit

// Renders the block screen shown over shielded apps and websites. Hard-blocked
// items get a variant with no unlock path.
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

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        if let token = application.token,
           SharedStore.shared.hardSelection.applicationTokens.contains(token) {
            return hardBlocked()
        }
        return unlockable()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let hard = SharedStore.shared.hardSelection
        if let token = application.token, hard.applicationTokens.contains(token) {
            return hardBlocked()
        }
        if let token = category.token, hard.categoryTokens.contains(token) {
            return hardBlocked()
        }
        return unlockable()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        if let token = webDomain.token,
           SharedStore.shared.hardSelection.webDomainTokens.contains(token) {
            return hardBlocked()
        }
        return unlockable()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let hard = SharedStore.shared.hardSelection
        if let token = webDomain.token, hard.webDomainTokens.contains(token) {
            return hardBlocked()
        }
        if let token = category.token, hard.categoryTokens.contains(token) {
            return hardBlocked()
        }
        return unlockable()
    }
}
