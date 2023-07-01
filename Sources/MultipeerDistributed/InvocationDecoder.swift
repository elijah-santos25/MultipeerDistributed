// InvocationDecoder.swift

import Foundation
import Distributed

/// Don't interact with this struct; it's only public due to protocol requirements.
public struct InvocationDecoder: DistributedTargetInvocationDecoder {
    fileprivate enum InvocationDecodingError: Int, DistributedActorSystemError {
        case tooFewArguments = 0
        case invalidGenericSubstitution = 1
    }
    public typealias SerializationRequirement = Codable
    fileprivate var container: RemoteCallContainer
    private var parent: MultipeerActorSystem
    
    init(container: RemoteCallContainer, actorSystem: MultipeerActorSystem) {
        self.container = container
        self.parent = actorSystem
    }
    
    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        guard container.arguments.count > 0 else {
            throw InvocationDecodingError.tooFewArguments
        }
        return try JSONDecoder().withActorSystem(parent).decode(Argument.self, from: container.arguments.removeFirst())
    }
    
    public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
        return try container.genericSubstitutions.map { name in
            guard let type = _typeByName(name) else {
                throw InvocationDecodingError.invalidGenericSubstitution
            }
            return type
        }
    }
    
    public mutating func decodeErrorType() throws -> (Any.Type)? {
        return container.throws ? Error.self : nil
    }
    
    public mutating func decodeReturnType() throws -> (Any.Type)? {
        // legal per the documentation of DistributedTargetInvocationDecoder.decodeReturnType()
        return nil
    }
}
