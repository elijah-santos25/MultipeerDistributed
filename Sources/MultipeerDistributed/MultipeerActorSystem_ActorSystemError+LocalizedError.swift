//
//  MultipeerActorSystem_ActorSystemError+LocalizedError.swift
//  
//
//  Created by Elijah Santos on 5/26/23.
//

import Foundation

extension MultipeerActorSystem.ActorSystemError: LocalizedError {
    public var localizedDescription: String {
        switch self {
        case .unknownRemoteActor:
            return NSLocalizedString(
                "MultipeerDistributed.unknownRemoteActorError",
                value: "The remote actor couldn't be resolved.",
                comment: "Tried to resolve an actor that isn't local and is unknown"
            )
        case .wrongTypeResolution:
            return NSLocalizedString(
                "MultipeerDistributed.wrongTypeResolutionError",
                value: "The local actor could not be resolved as the provided type.",
                comment: "Tried to resolve an actor that is local but as the wrong type"
            )
        case .notConnected:
            return NSLocalizedString(
                "MultipeerDistributed.notConnectedError",
                value: "The device is not connected to any others.",
                comment: "Tried to perform a remote call while not connected"
            )
        case .actorOwnerNotConnected:
            return NSLocalizedString(
                "MultipeerDistributed.actorOwnerNotConnectedError",
                value: "The device is not connected to the owner of the actor.",
                comment: "Tried to perform a remote call while not connected to the device that owns the actor"
            )
        case .systemError:
            return NSLocalizedString(
                "MultipeerDistributed.systemErrorError",
                value: "An error occurred while performing remote operations.",
                comment: "A generic error occurred in MultipeerDistributed"
            )
        }
    }
}
