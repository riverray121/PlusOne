import Foundation
import ManagedSettings

// The single blocked item a selfie pass will unlock. Tokens are opaque and
// only valid against the selection that produced them.
enum UnlockTarget: Codable, Equatable {
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
    case category(ActivityCategoryToken)
    // String-typed domain from PlusOne's own blocklist (content filter), as
    // opposed to a picker-issued WebDomainToken.
    case domain(String)

    var displayNoun: String {
        switch self {
        case .application: return "app"
        case .webDomain, .domain: return "website"
        case .category: return "category"
        }
    }
}
