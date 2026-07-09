import Foundation

struct AuthUser: Codable, Identifiable, Hashable {
    let id: Int
    let qq: String
    let role: String
    let expiresAt: String?
    let isActive: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, qq, role
        case expiresAt = "expires_at"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    var isSuperAdmin: Bool { role == "super_admin" }
    var displayRole: String { isSuperAdmin ? "超级管理员" : "管理员" }
}

struct AuthResponse: Codable {
    let token: String
    let user: AuthUser
}

struct EngineLine: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let enabled: Bool
}

struct CardKeyItem: Codable, Identifiable, Hashable {
    let id: Int
    let cardKey: String
    let durationDays: Int
    let note: String
    let isUsed: Bool
    let usedByUserId: Int?
    let usedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case cardKey = "card_key"
        case durationDays = "duration_days"
        case note
        case isUsed = "is_used"
        case usedByUserId = "used_by_user_id"
        case usedAt = "used_at"
        case createdAt = "created_at"
    }
}
