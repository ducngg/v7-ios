//
//  Constants.swift
//
//  Created by Ethan Sarif-Kattan on 10/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//

import Foundation
import UIKit

enum Constants{
    static let MAX_SEQUENCE_LEN = 32
    static let VOCAB_SIZE = 21869
    static let MODEL = "v7gpt-2.1-small-20250903-fp16"
    static let TOP_K = 128
    static let TOP_K_SHOWING = 24
    static let MAX_FILTER_ITERATE = 4096
    
    static let TEMPERATURE: Float = 1.0
    static let BIAS_ALPHA: Float = 0.3
    static let BIAS_INCREMENT_STEP: Float = 50 / Float(VOCAB_SIZE)
    
    static let activationThreshold: CGFloat = 5.0

    static let fakeClear: UIColor = UIColor(white: 0.1, alpha: 0.01) // If using clear then very hard to press button
    static let textColor: UIColor = {
        if UITraitCollection.current.userInterfaceStyle == .dark {
            return UIColor.white
        } else {
            return UIColor.black
        }
    }()
    static let backgroundColor: UIColor = {
        if UITraitCollection.current.userInterfaceStyle == .dark {
            return fakeClear
        } else {
            return UIColor(white: 0.95, alpha: 0.35)
        }
    }()

//	static let keyNormalColour: UIColor = .white
    static let keyNormalColour: UIColor = fakeClear // .clear
    static let keyPressedColour: UIColor = UIColor(white: 0.85, alpha: 0.2)
    
//    static let specialKeyNormalColour: UIColor = UIColor(white: 0.85, alpha: 1.0)
    static let specialKeyNormalColour: UIColor = fakeClear
    
    // Radial Menu Colors
    static let radialMenuSelected: CGColor = UIColor.systemBlue.withAlphaComponent(0.95).cgColor
    static let radialMenuUnselected: CGColor = {
        if UITraitCollection.current.userInterfaceStyle == .dark {
            return UIColor(white: 0.2, alpha: 0.9).cgColor
        } else {
            return UIColor(white: 0.95, alpha: 0.9).cgColor
        }
    }()
    static let defaultToneDisplay: String = "ᯅ"

    
	static let letterKeys = [
		["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], 
		["a", "s", "d", "f", "g","h", "j", "k", "l"],
		["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
		["123", "☻", "dấu cách", "⏎"]
	]
	static let numberKeys = [
		["1", "2", "3", "4", "5", "6", "7", "8", "9", "0",],
		["-", "/", ":", ";", "(", ")" ,",", "$", "&", "@", "\""],
		["#+=",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "☻", "dấu cách", "⏎"]
	]
	
	static let symbolKeys = [
		["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
		["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
		["123",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "☻", "dấu cách", "⏎"]
	]
    static let specialKeys = ["⇧", "⌫", "#+=", "ABC", "123", "☻", "⏎"]
    
    static let modalParticles = [
        "nhé", "nha", "nhe", "nhá",
        "ạ", "dạ", "vậy", "ơi", "ui", "ới",
        "đi", "i",
        "nè",
        "chứ", "chớ",
        "mà",
        "cơ",
        "thôi", "thui",
        "á", "đó", "ó", "đấy",
        "hả", "hở", "nhỉ",
        "à", "òm", "ồ", "ư",
        "ha",
        "hong", "không",
        "luôn",
    ]
    
    static let allowedRadialKeys: Set<String> = {
        var keys = Set((97...122).map { String(UnicodeScalar($0)! ) }) // a–z
        keys.insert("dấu cách") // dấu cách
        return keys
    }()
}
