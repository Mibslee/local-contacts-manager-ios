//
//  Item.swift
//  本地通讯录管家
//
//  Created by Peishen Li on 2026/3/20.
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
