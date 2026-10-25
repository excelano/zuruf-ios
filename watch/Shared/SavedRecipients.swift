// SavedRecipients.swift
// Shared
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// The people and groups on the server, for the Talk to complication to offer.
enum SavedRecipients {
    private static let service = "zuruf.recipients"

    static func load() -> [Recipient] {
        Keychain.data(service).flatMap { try? JSONDecoder().decode([Recipient].self, from: $0) } ?? []
    }

    static func save(_ recipients: [Recipient]) {
        try? Keychain.set(JSONEncoder().encode(recipients), for: service)
    }

    static func clear() {
        Keychain.delete(service)
    }
}

extension Recipient {
    // Stable across renames, for a complication to remember who it opens.
    var key: String {
        switch self {
        case .person(let id, _): "person:\(id)"
        case .group(let id, _): "group:\(id)"
        }
    }

    // Up to two letters, from the first two words of the name.
    var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
}
