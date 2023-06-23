// Message.swift
//
// A message sent via the MCSession (wraps all message types).

import Foundation

enum Message: Codable {
    case actorsAvailable(actors: [ActorRecord])
    case performRemoteCall(callID: UUID, targetActorID: ActorID, RemoteCallContainer)
    case remoteCallResponse(callID: UUID, Response)
}
