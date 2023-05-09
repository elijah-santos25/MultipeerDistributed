// Receptionist.swift
//
// Sort-of implements a receptionist pattern like the one
// in the "Tic-Tac-Fish" WWDC session (although this one
// just provides a window into the MultipeerActorSystem)

import Foundation
import Distributed

/// Makes actors known to remote peers, and provides a method to listen for actors.
public actor Receptionist<IDType: Hashable>: Sendable {
    init(parent: MultipeerActorSystem) {
        self.parent = parent
    }
    
    unowned private let parent: MultipeerActorSystem
    private var actorReceivers: [UUID: (any DistributedActor, Data) async -> Void] = [:]
    
    /// Makes `actor` available to connected peers, alongside a program-defined tag.
    /// - Parameters:
    ///   - actor: The actor to expose remotely.
    ///   - tag: An arbitrary `Data` that will be associated with the actor in receptionist listings.
    ///   This does not have to be unique.
    public func startAdvertising<Act: DistributedActor>(actor: Act, tag: Data)
    where Act.ID == IDType, Act.ActorSystem == MultipeerActorSystem {
        parent.startAdvertising(actor, tag: tag)
    }
    
    /// Removes `actor` from the list of advertised actors (it may take a few seconds for
    /// the actor to disappear on other devices).
    ///
    /// Note that any actors already emitted via `actors(ofType:)` can't be "unpublished",
    /// they will just fail to resolve.
    public func stopAdvertising<Act: DistributedActor>(actor: Act)
    where Act.ID == IDType, Act.ActorSystem == MultipeerActorSystem {
        parent.stopAdvertising(actor)
    }
    
    /// Returns an `AsyncStream` of the specified actor type and associated tags which will yield values
    /// as they are made known to the receptionist.
    ///
    /// This will immediately yield all already-known actors and their tags first.
    /// - Parameter type: The type of distributed actor to listen for.
    /// - Returns: An `AsyncStream` of actor listings as they are advertised (starting with those already received).
    public func actors<Act: DistributedActor>(ofType type: Act.Type) -> AsyncStream<(Act, Data)>
    where Act.ID == IDType, Act.ActorSystem == MultipeerActorSystem {
        let listenerID = UUID()
        let stream = AsyncStream((Act, Data).self) { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    if let self {
                        await self.removeListener(id: listenerID)
                    }
                }
            }
            let handlerClosure = { [continuation] (untypedActor: any DistributedActor, tag: Data) in
                if let typedActor = untypedActor as? Act {
                    // only notify about actors of the correct type
                    continuation.yield((typedActor, tag))
                }
            }
            for (alreadyKnownActor, tag) in parent.knownActors() {
                handlerClosure(alreadyKnownActor, tag)
            }
            actorReceivers[listenerID] = handlerClosure
        }
        return stream
    }
    
    // internal interface
    
    internal func newActor(_ actor: any DistributedActor, tag: Data) {
        self.actorReceivers.values.forEach { receiver in
            Task {
                await receiver(actor, tag)
            }
        }
    }
    
    // private mutations
    
    private func removeListener(id: UUID) {
        self.actorReceivers.removeValue(forKey: id)
    }
}
