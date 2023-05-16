// TaggedData.swift
//
// Wraps data sent over the MCSession so the actor system
// ignores non-actor-system messages.

import Foundation

struct TaggedData<T: Codable>: Codable {
    init(_ value: T) {
        self.value = value
    }
    
    private static var tag: String { "MultipeerDistributed" }
    enum CodingKeys: CodingKey {
        case value
        // This only exists to change the shape of the JSON
        case __data_tag__
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<TaggedData<T>.CodingKeys> = try decoder.container(keyedBy: TaggedData<T>.CodingKeys.self)
        guard (try? container.decode(String.self, forKey: .__data_tag__)) == TaggedData.tag else {
            throw DecodingError.keyNotFound(
                CodingKeys.__data_tag__,
                .init(codingPath: container.codingPath, debugDescription: "Missing key __data_tag__.")
            )
        }
        self.value = try container.decode(T.self, forKey: TaggedData<T>.CodingKeys.value)
        
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TaggedData<T>.CodingKeys.self)
        try container.encode(TaggedData.tag, forKey: .__data_tag__)
        try container.encode(self.value, forKey: .value)
    }
    
    let value: T
}
