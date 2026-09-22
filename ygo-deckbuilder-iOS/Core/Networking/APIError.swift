import Foundation

nonisolated struct APIError: LocalizedError, Sendable {
    nonisolated struct Issue: Decodable, Sendable {
        let path: String
        let message: String
    }

    let status: Int
    let message: String
    var issues: [Issue] = []

    var errorDescription: String? {
        guard !issues.isEmpty else { return message }
        return ([message] + issues.map { "\($0.path): \($0.message)" }).joined(separator: "\n")
    }

    var isUnauthorized: Bool { status == 401 }
    var isNotFound: Bool { status == 404 }

    /// Corps d'erreur NestJS : { message: string | string[], issues?: [...] }.
    static func from(status: Int, data: Data) -> APIError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        return APIError(
            status: status,
            message: body?.message?.text ?? HTTPURLResponse.localizedString(forStatusCode: status),
            issues: body?.issues ?? []
        )
    }
}

nonisolated private struct ErrorBody: Decodable {
    let message: ErrorMessage?
    let issues: [APIError.Issue]?
}

nonisolated private enum ErrorMessage: Decodable {
    case one(String), many([String])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .one(s)
        } else {
            self = .many(try c.decode([String].self))
        }
    }

    var text: String {
        switch self {
        case .one(let s): s
        case .many(let xs): xs.joined(separator: ", ")
        }
    }
}
