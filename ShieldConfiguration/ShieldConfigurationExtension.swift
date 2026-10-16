import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Pinta de negro la pantalla que iOS muestra al abrir una app bloqueada durante
/// una grabación, para que el teléfono parezca apagado.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.blackShield
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.blackShield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.blackShield
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.blackShield
    }

    private static var blackShield: ShieldConfiguration {
        let invisible = ShieldConfiguration.Label(text: " ", color: .black)
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: .black,
            icon: blackIcon,
            title: invisible,
            subtitle: invisible,
            primaryButtonLabel: invisible,
            primaryButtonBackgroundColor: .black,
            secondaryButtonLabel: nil
        )
    }

    private static let blackIcon: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()
}
