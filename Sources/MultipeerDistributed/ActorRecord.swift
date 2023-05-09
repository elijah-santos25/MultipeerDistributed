// ActorRecord.swift
//
// A representation of a remote actor.

import Foundation
import Distributed

struct ActorRecord: Codable {
    let type: String
    let id: UUID
    let tag: Data
}

extension ActorRecord {
    init<T: DistributedActor>(actor: T, tag: Data) where T.ID == UUID {
        self.type = _typeName(T.self)
        self.id = actor.id
        self.tag = tag
    }
}
