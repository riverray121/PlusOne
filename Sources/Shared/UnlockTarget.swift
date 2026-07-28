import Foundation
import ManagedSettings

// The single blocked item a selfie pass will unlock. Tokens are opaque and
// only valid against the selection that produced them.
enum UnlockTarget: Codable, Equatable {
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
    case category(ActivityCategoryToken)

    var displayNoun: String {
        switch self {
        case .application: return "app"
        case .webDomain: return "website"
        case .category: return "category"
        }
    }
}
