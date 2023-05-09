// MultipeerSessionHandler.swift
//
// Manages the underlying MCSession (it's the delegate).

import Foundation
import MultipeerConnectivity

@objc internal class MultipeerSessionHandler: NSObject, MCSessionDelegate {
    internal init(parent: MultipeerActorSystem) {
        self.parent = parent
    }
    private var session: MCSession? = nil
    private weak var forwardingDelegate: (any MCSessionDelegate)? = nil
    private unowned let parent: MultipeerActorSystem
    
    func takeover(_ session: MCSession) {
        self.session = session
        self.forwardingDelegate = session.delegate
        session.delegate = self
    }
    
    func isConnected(to peer: MCPeerID) -> Bool {
        return session?.connectedPeers.contains(peer) ?? false
    }
    
    func send(_ message: Message, to peer: MCPeerID) throws {
        try session?.send(JSONEncoder().encode(message), toPeers: [peer], with: .reliable)
    }
    
    func broadcast(_ message: Message) throws {
        try session?.send(JSONEncoder().encode(message), toPeers: session?.connectedPeers ?? [], with: .reliable)
    }
    
    
    // MARK: - Delegate Implementations
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        forwardingDelegate?.session(session, peer: peerID, didChange: state)
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let decoder = JSONDecoder()
        decoder.userInfo[.actorSystemKey] = parent
        if let tagged = try? decoder.decode(TaggedData<Message>.self, from: data) {
            // this is our message, so process it
            parent.receivedMessage(tagged.value, from: peerID)
        } else {
            // not our message; forward to old delegate
            forwardingDelegate?.session(session, didReceive: data, fromPeer: peerID)
        }
    }
    
    // we don't care about the following methods; just forward them
    
    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        forwardingDelegate?.session(session, didReceive: stream, withName: streamName, fromPeer: peerID)
    }
    
    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        forwardingDelegate?.session(session, didStartReceivingResourceWithName: resourceName, fromPeer: peerID, with: progress)
    }
    
    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        forwardingDelegate?.session(
            session,
            didFinishReceivingResourceWithName: resourceName,
            fromPeer: peerID,
            at: localURL,
            withError: error
        )
    }
    
    func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        forwardingDelegate?.session?(
            session,
            didReceiveCertificate: certificate,
            fromPeer: peerID,
            certificateHandler: certificateHandler
        )
    }
}
