//
//  Item.swift
//  Wandr
//
//  Created by aryaman jaiswal on 18/07/26.
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
