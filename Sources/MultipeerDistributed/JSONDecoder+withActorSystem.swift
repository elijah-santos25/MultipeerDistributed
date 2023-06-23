// JSONDecoder+withActorSystem.swift

import Foundation
import Distributed

internal extension JSONDecoder {
    func withActorSystem(_ actorSystem: some DistributedActorSystem) -> Self {
        self.userInfo[.actorSystemKey] = actorSystem
        return self
    }
}
