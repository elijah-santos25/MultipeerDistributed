// InvocationEncoder.swift

import Foundation
import Distributed

/// Don't interact with this struct; it's only public due to protocol requirements.
public struct InvocationEncoder: DistributedTargetInvocationEncoder {
    var container = RemoteCallContainer()
    public mutating func recordArgument<Value: SerializationRequirement>(
        _ argument: RemoteCallArgument<Value>
    ) throws {
        container.arguments.append(try JSONEncoder().encode(argument.value))
    }
    
    public mutating func recordReturnType<R: SerializationRequirement>(_ type: R.Type) throws {
        container.returnType = _typeName(type)
    }
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        container.genericSubstitutions.append(_typeName(type))
    }
    
    public mutating func recordErrorType<E>(_ type: E.Type) throws where E: Error {
        container.throws = true
    }
    
    public mutating func doneRecording() throws {
        
    }
    
    public typealias SerializationRequirement = Codable
}
