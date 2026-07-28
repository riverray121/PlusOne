import ManagedSettings
import ManagedSettingsUI
import UIKit

// Renders the block screen shown over shielded apps and websites.
class ShieldConfigurationProvider: ShieldConfigurationDataSource {

    private func makeConfiguration() -> ShieldConfiguration {
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

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }
}
