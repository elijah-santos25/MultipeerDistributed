// RemoteCallContainer.swift
//
// Remote calls are encoded into this struct.

import Foundation

struct RemoteCallContainer: Codable {
    var methodIdentifier: String = ""
    var arguments: [Data] = []
    var genericSubstitutions: [String] = []
    var returnType: String? = nil
    var `throws` = false
}
