//
//  Persistable.swift
//  
//
//  Created by Antwan van Houdt on 16/01/2021.
//

import Foundation

protocol Persistable: Codable {
    var id: UUID? { get }
}
