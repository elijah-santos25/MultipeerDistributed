// InvocationDecoder.swift

import Foundation
import Distributed

/// Don't interact with this struct; it's only public due to protocol requirements.
public struct InvocationDecoder: DistributedTargetInvocationDecoder {
    fileprivate enum InvocationDecodingError: DistributedActorSystemError {
        fileprivate enum InvalidReason: String {
            case unexpected
            case noMatchingType
        }
        case tooFewArguments
        case tooFewGenericSubstitutions
        case invalidGenericSubstitution
        case invalidReturnType(InvalidReason)
        case invalidErrorType(InvalidReason)
    }
    public typealias SerializationRequirement = Codable
    fileprivate var container: RemoteCallContainer
    
    init(container: RemoteCallContainer) {
        self.container = container
    }
    
    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        guard container.arguments.count > 0 else {
            throw InvocationDecodingError.tooFewArguments
        }
        return try JSONDecoder().decode(Argument.self, from: container.arguments.removeFirst())
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
