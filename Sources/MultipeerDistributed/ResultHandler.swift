// ResultHandler.swift

import Foundation
import Distributed

/// Don't interact with this struct; it's only public due to protocol requirements.
public struct ResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable
    
    let voidReturnHandler: () async throws -> Void
    let valueReturnHandler: (Data) async throws -> Void
    let throwHandler: (Error) async throws -> Void
    
    internal init(
        voidReturnHandler: @escaping () -> Void,
        valueReturnHandler: @escaping (Data) -> Void,
        throwHandler: @escaping (Error) -> Void
    ) {
        self.voidReturnHandler = voidReturnHandler
        self.valueReturnHandler = valueReturnHandler
        self.throwHandler = throwHandler
    }
    
    public func onReturnVoid() async throws {
        try await voidReturnHandler()
    }
    
    public func onThrow<Err>(error: Err) async throws where Err : Error {
        try await throwHandler(error)
    }
    
    public func onReturn<Success: Codable>(value: Success) async throws {
        try await valueReturnHandler(JSONEncoder().encode(value))
    }
}
