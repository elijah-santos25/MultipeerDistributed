// MultipeerActorSystem.swift
//
// The MultipeerConnectivity-based distributed actor system.

import Foundation
import Distributed
import MultipeerConnectivity
import os

/// A `MultipeerConnectivity`-based distributed actor system implementation.
public final class MultipeerActorSystem: DistributedActorSystem, @unchecked Sendable {
    // Sendable conformance: NSLock-synchronized
    public typealias ActorID = MultipeerDistributed.ActorID
    public typealias InvocationEncoder = MultipeerDistributed.InvocationEncoder
    public typealias InvocationDecoder = MultipeerDistributed.InvocationDecoder
    public typealias ResultHandler = MultipeerDistributed.ResultHandler
    public typealias SerializationRequirement = Codable
    
    public enum ActorSystemError: DistributedActorSystemError {
        // trying to resolve an unknown actor
        case unknownRemoteActor
        // trying to resolve a local reference as the wrong type
        case wrongTypeResolution
        case notConnected
        // the peer that owns the actor is no longer connected
        case actorOwnerNotConnected
        // something went wrong on our end
        case systemError
    }
    
    private static var logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "unknown-bundle-id", category: "MultipeerActorSystem")
    
    
    // MARK: - Public API
    
    public init() {
        self.receptionist = .init(parent: self)
        
        self.advertisingTask = Task { [weak self] in
            while let self {
                self.lock.withLock {
                    guard let multipeerHandler = self.multipeerHandler, multipeerHandler.hasPeers else {
                        return
                    }
                    
                    do {
                        try multipeerHandler.broadcast(
                            .actorsAvailable(actors: self.actorsToAdvertise.compactMap { (actor, tag) in
                                guard let id = actor.id as? ActorID else {
                                    return nil
                                }
                                let typeName = _typeName(type(of: actor))
                                return ActorRecord(type: typeName, id: id, tag: tag)
                            })
                        )
                    } catch {
                        MultipeerActorSystem.logger.info("Couldn't advertise even though handler exists: \(error.localizedDescription)")
                    }
                }
                do {
                    try await SuspendingClock().sleep(until: .now.advanced(by: .seconds(5)), tolerance: .seconds(1))
                } catch {
                    if error is CancellationError {
                        return
                    }
                }
            }
        }
    }
    
    /// Gives control of the `MCSession` to the `MultipeerActorSystem`.
    /// Messages sent over the session should still reach the preexisting delegate.
    ///
    /// - Important: Do not set the `delegate` property of the `MCSession` after calling this
    /// method; this would interfere with the `MultipeerActorSystem`. If you do need to change it,
    /// set the `delegate` property then call this method again.
    /// - Parameter session: The `MCSession` to be used to transmit remote calls from now on. Its
    /// delegate will continue to receive messages.
    public func setSession(_ session: MCSession) {
        if self.multipeerHandler == nil {
            self.multipeerHandler = .init(parent: self)
        }
        
        self.multipeerHandler!.takeover(session)
    }
    /// The ``Receptionist`` in charge of advertising available actors to peers.
    public private(set) var receptionist: Receptionist<ActorID>!
    
    
    // MARK: - Private
    
    private let lock = NSLock()
    private var managedActors: [ActorID: (any DistributedActor)?] = [:]
    private var actorsToAdvertise: [(any DistributedActor, Data)] = []
    private var knownRemoteActors: [MCPeerID: [ActorRecord]] = [:]
    private var inflightCalls: [UUID: (Response) -> Void] = [:]
    private var multipeerHandler: MultipeerSessionHandler? = nil
    private var advertisingTask: Task<Void, Never>? = nil
    
    
    private func sendInvocationContainer(_ container: RemoteCallContainer, call: UUID, actor: ActorID, to peer: MCPeerID) throws {
        guard let multipeerHandler else {
            throw ActorSystemError.notConnected
        }
        guard multipeerHandler.isConnected(to: peer) else {
            throw ActorSystemError.actorOwnerNotConnected
        }
        
        try multipeerHandler.send(.performRemoteCall(callID: call, targetActorID: actor, container), to: peer)
    }
    
    private func startRemoteCall<T: DistributedActor>(id: UUID, target: T, call: RemoteCallContainer, sender: MCPeerID) async {
        let response: Response
        do {
            response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Response, any Error>) in
                Task { [cont] in
                    var decoder = InvocationDecoder(container: call, actorSystem: self)
                    do {
                        try await executeDistributedTarget(
                            on: target,
                            target: .init(call.methodIdentifier),
                            invocationDecoder: &decoder,
                            handler: .init(voidReturnHandler: {
                                cont.resume(returning: Response.voidSuccess)
                            }, valueReturnHandler: { data in
                                // on the recipient end, this type will be known
                                cont.resume(returning: Response.success(data: data))
                            }, throwHandler: { err in
                                cont.resume(returning: Response(thrownError: err))
                            })
                        )
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } catch {
            response = .systemFailure
            MultipeerActorSystem.logger
                .info("Couldn't execute distributed target from \(sender.displayName): \(error.localizedDescription)")
        }
        do {
            try sendReply(response, call: id, to: sender)
        } catch {
            MultipeerActorSystem.logger.info("Couldn't send reply for remote call: \(error.localizedDescription)")
        }
    }
    
    private func sendReply(_ reply: Response, call: UUID, to peer: MCPeerID) throws {
        try lock.withLock {
            try multipeerHandler?.send(.remoteCallResponse(callID: call, reply), to: peer)
        }
    }
    
    /// Actually performs the remote call.
    ///
    /// This method's signature is slightly different from
    /// ``remoteCall(on:target:invocation:throwing:returning:)`` so both `remoteCall[Void]` methods
    /// can reuse implementation. (The difference is that this doesn't require `Res` to be `Codable`.)
    private func actualRemoteCall<Act: DistributedActor, Err: Error, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing errorType: Err.Type,
        returning returnType: Res.Type
    ) async throws -> Res where Act.ID == ActorID {
        return try await withCheckedThrowingContinuation { cont in
            let callID = UUID()
            self.lock.lock()
            defer { self.lock.unlock() }
            
            do {
                guard let multipeerHandler else {
                    throw ActorSystemError.notConnected
                }
                guard let peer = self.knownRemoteActors.first(where: { $0.key.displayName == actor.id.peer })?.key else {
                    throw ActorSystemError.unknownRemoteActor
                }
                guard multipeerHandler.isConnected(to: peer) else {
                    throw ActorSystemError.actorOwnerNotConnected
                }
                invocation.container.methodIdentifier = target.identifier
                try multipeerHandler.send(
                    .performRemoteCall(
                        callID: callID,
                        targetActorID: actor.id,
                        invocation.container
                    ),
                    to: peer
                )
            } catch {
                cont.resume(throwing: error)
                return
            }
            
            self.inflightCalls[callID] = { [cont] response in
                if let result = response.toResult(expecting: returnType, using: self) {
                    cont.resume(with: result)
                } else {
                    cont.resume(throwing: ActorSystemError.systemError)
                }
            }
            
        }
    }
    
    
    // MARK: - Internal Interface
    
    func knownActors() -> some Sequence<(any DistributedActor, Data)> {
        func resolveConcrete<A: DistributedActor & Codable>(_ type: A.Type, id: ActorID) -> (any DistributedActor & Codable)? {
            guard let self = self as? A.ActorSystem, let id = id as? A.ID else {
                return nil
            }
            return try? type.resolve(id: id, using: self)
        }
        
        return self.lock.withLock { self.knownRemoteActors }.values.joined().compactMap { record -> (any DistributedActor, Data)? in
            guard let type = _typeByName(record.type) as? any (Codable & DistributedActor).Type,
                  let resolved = resolveConcrete(type, id: record.id) else {
                MultipeerActorSystem.logger.info("Couldn't resolve local actor of type \(record.type)")
                return nil
            }
            
            return (resolved, record.tag)
        }
    }
    
    func receivedMessage(_ message: Message, from peer: MCPeerID) {
        self.lock.lock()
        
        MultipeerActorSystem.logger.trace("Received message \(String(reflecting: message)) from \(peer.displayName).")
        
        // TODO: Refactor to be less ugly
        switch message {
        case .actorsAvailable(let actors):
            self.knownRemoteActors[peer] = actors
            Task { [weak self, actors] in
                func resolveConcrete<A: DistributedActor & Codable>(_ type: A.Type, id: ActorID) -> (any DistributedActor & Codable)? {
                    guard let self = self as? A.ActorSystem, let id = id as? A.ID else {
                        return nil
                    }
                    return try? type.resolve(id: id, using: self)
                }
                for actor in actors {
                    guard let type = _typeByName(actor.type) as? any (DistributedActor & Codable).Type else {
                        MultipeerActorSystem.logger.info("Unknown actor type \(actor.type).")
                        continue
                    }
                    // implicitly opened existentials save the day!
                    if let resolved = resolveConcrete(type, id: actor.id) {
                        await self?.receptionist.newActor(resolved, tag: actor.tag)
                    }
                }
            }
            self.lock.unlock()
        case .performRemoteCall(let callID, let targetActorID, let remoteCallContainer):
            if let actor = self.managedActors[targetActorID], let actor {
                Task {
                    await startRemoteCall(id: callID, target: actor, call: remoteCallContainer, sender: peer)
                }
            } else {
                MultipeerActorSystem.logger.info("Peer \(peer.displayName) tried to perform a remote call on an actor we don't have.")
                try? multipeerHandler?.send(
                    .remoteCallResponse(callID: callID, .systemFailure), to: peer
                )
            }
            self.lock.unlock()
        case .remoteCallResponse(let callID, let response):
            guard let call = inflightCalls.removeValue(forKey: callID) else {
                MultipeerActorSystem.logger.info(
                    "Received response for unknown/completed remote call (id: \(callID, privacy: .public), \(String(reflecting: response))"
                )
                return
            }
            self.lock.unlock()
            call(response)
        }
    }
    
    func startAdvertising(_ a: some DistributedActor, tag: Data) {
        self.actorsToAdvertise.append((a, tag))
    }
    
    func stopAdvertising(_ a: some DistributedActor) {
        self.actorsToAdvertise.removeAll { existing in
            existing.0.id == a.id
        }
    }
    
    
    // MARK: - DistributedActorSystem Requirements
    // Only public due to protocol requirements.
    
    public func remoteCall<Act: DistributedActor, Err: Error, Res: Codable>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing errorType: Err.Type,
        returning returnType: Res.Type
    ) async throws -> Res where Act.ID == ActorID {
        // see the documentation for `actualRemoteCall(on:target:invocation:throwing:returning:)`
        // for why it exists
        return try await self.actualRemoteCall(
            on: actor,
            target: target,
            invocation: &invocation,
            throwing: errorType,
            returning: returnType
        )
    }
    
    public func remoteCallVoid<Act: DistributedActor, Err: Error>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing errorType: Err.Type
    ) async throws where Act.ID == ActorID {
        // see the documentation for `actualRemoteCall(on:target:invocation:throwing:returning:)`
        // for why it exists
        return try await self.actualRemoteCall(
            on: actor,
            target: target,
            invocation: &invocation,
            throwing: errorType,
            returning: Void.self
        )
    }
    
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? where Act : DistributedActor, ActorID == Act.ID {
        self.lock.lock()
        defer { self.lock.unlock() }
        
        if let optionalLocal = self.managedActors[id] {
            guard let untypedLocal = optionalLocal else {
                // if this fails: either some cleanup didn't happen or an actor is in the process of initialization.
                preconditionFailure("Trying to resolve an actor ID that is assigned but not initialized!")
            }
            
            guard let typedLocal = untypedLocal as? Act else {
                throw ActorSystemError.wrongTypeResolution
            }
            
            return typedLocal
        }
        
        // if it's not in the managed actors list, it should match another peer's id
        if self.knownRemoteActors.keys.map(\.displayName).contains(id.peer) {
            return nil
        } else {
            throw ActorSystemError.unknownRemoteActor
        }
    }
    
    public func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act : DistributedActor, Act.ID == ActorID {
        self.lock.lock()
        defer { self.lock.unlock() }
        
        let newID = ActorID(peer: multipeerHandler?.myPeerID?.displayName ?? "")
        
        self.managedActors[newID] = nil
        return newID
    }
    
    public func actorReady<Act>(_ actor: Act) where Act : DistributedActor, Act.ID == ActorID {
        self.lock.lock()
        defer { self.lock.unlock() }
        
        self.managedActors[actor.id] = actor
    }
    
    public func resignID(_ id: ActorID) {
        self.lock.lock()
        defer { self.lock.unlock() }
        
        // if this fails, someone is either misusing the system
        // or a programming error occurred; either way, program shouldn't continue
        precondition(self.managedActors.keys.contains(id), "Can't resign an unassigned ID!")
        
        self.managedActors.removeValue(forKey: id)
        self.actorsToAdvertise.removeAll { (act, _) in
            act.id as? ActorID == id
        }
    }
    
    public func makeInvocationEncoder() -> InvocationEncoder {
        return .init()
    }
}
