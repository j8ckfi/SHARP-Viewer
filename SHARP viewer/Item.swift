//
//  Item.swift
//  SHARP viewer
//
//  Created by Jack Large on 12/26/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
