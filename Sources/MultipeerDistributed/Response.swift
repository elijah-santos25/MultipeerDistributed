// Response.swift
//
// The data sent in response to a remote call.

import Foundation

enum Response: Codable {
    private struct GenericError: LocalizedError {
        private let description: String
        
        init(description: String) {
            self.description = description
        }
        
        var errorDescription: String { description }
    }
    
    /// An error was thrown that conforms to `Codable`.
    case wrappingError(typeName: String, data: Data)
    /// An error was thrown that couldn't be encoded (even if the type is nominally `Codable`).
    case nonCodableError(typeName: String, description: String)
    /// Operation successful (returned something `Codable`).
    case success(data: Data)
    /// Operation successful (returned `Void`).
    case voidSuccess
    /// Operation unsuccessful due to the actor system.
    case systemFailure
    
    init(thrownError: Error) {
        // make a best-effort attempt to encode an error (still encode something if it can't)genergee
        if let thrownError = thrownError as? any (Error & Codable),
           let encodedData = try? JSONEncoder().encode(thrownError) {
            self = .wrappingError(typeName: _typeName(type(of: thrownError as Any)), data: encodedData)
        } else {
            self = .nonCodableError(
                typeName: String(describing: thrownError as Any),
                description: thrownError.localizedDescription
            )
        }
    }
    
    init?(success: some Codable) {
        if let data = try? JSONEncoder().encode(success) {
            self = .success(data: data)
        } else {
            return nil
        }
    }
    
    init(voidSuccess: Void) {
        self = .voidSuccess
    }
    
    func toResult<Success>(
        expecting expectedSuccessType: Success.Type,
        using actorSystem: MultipeerActorSystem
    ) -> Result<Success, Error>? {
        switch self {
        case .wrappingError(typeName: let typeName, data: let data):
            func genericDecode<T: Codable & Error>(type: T.Type, data: Data) -> (any (Codable & Error))? {
                if let value = try? JSONDecoder().withActorSystem(actorSystem).decode(type, from: data) {
                    return value
                } else {
                    return nil
                }
            }
            if let type = _typeByName(typeName) as? (Codable & Error).Type,
               let value = genericDecode(type: type, data: data) {  // hooray for implicitly opened existentials
                return .failure(value)
            } else {
                return .failure(GenericError(description: "Couldn't decode error\(typeName)."))
            }
        case .nonCodableError(typeName: let typeName, description: let description):
            return .failure(GenericError(description: "\(typeName): \(description)"))
        case .success(data: let data):
            if let expectedSuccessType = expectedSuccessType as? any Codable.Type {
                if let value = try? JSONDecoder().withActorSystem(actorSystem).decode(expectedSuccessType, from: data) as? Success {
                    return .success(value)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        case .voidSuccess:
            if Success.self == Void.self {
                // we know success is Void due to the above check, force-cast allowed
                return .success(() as! Success)
            } else {
                // .voidSuccess when not expecting Void is invalid
                return nil
            }
        case .systemFailure:
            return .failure(MultipeerActorSystem.ActorSystemError.unknownRemoteActor)
        }
    }
}
