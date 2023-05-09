# MultipeerDistributed

An attempt at a distributed actor system built on top of `MultipeerConnectivity`.

## How to Use

### Use Distributed Actors

1. Create the `MCSession` and connect peers however you want.
1. Hand it over to the `MultipeerActorSystem`. All non-actor system delegate messages will 
   be forwarded to your delegate, and you can still send messages via the `MCSession`.
1. Perform remote calls on your distributed actors!

### Actor Discovery

- Use the `receptionist` property of to publish local and discover remote actors

## Miscellaneous Info

- Makes a best-effort attempt to encode and decode errors thrown by remote calls.
