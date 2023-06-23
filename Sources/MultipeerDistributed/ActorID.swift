// ActorID.swift
//  
// The ID type that all distributed actors have. Contains a UUID for
// uniqueing and the displayName of the peer it comes from.

import Foundation

public struct ActorID: Codable, Hashable, Equatable {
    init(peer: String) {
        self.uuid = .init()
        self.peer = peer
    }
    var uuid: UUID
    var peer: String
}
