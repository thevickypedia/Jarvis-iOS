//
//  Utils.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import Foundation

func convertStringToHex(_ str: String) -> String {
    Log.info("🔐 Converting token to hex")
    return str.unicodeScalars.map {
        let hex = String($0.value, radix: 16)
        return String(repeating: "0", count: 4 - hex.count) + hex
    }.joined(separator: "\\u")
}
