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
//    static let MODEL = "v7gpt-large-20250511"
    static let MODEL = "v7gpt-2.1-small-20250903-fp16"
    static let TOP_K = 512
    static let TOP_K_SHOWING = 7
    static let MAX_FILTER_ITERATE = 8192

    static let textColor: UIColor = {
        if UITraitCollection.current.userInterfaceStyle == .dark {
            return UIColor.white
        } else {
            return UIColor.black
        }
    }()
    static let backgroundColor: UIColor = {
        if UITraitCollection.current.userInterfaceStyle == .dark {
            return UIColor.darkGray
        } else {
            return UIColor(white: 0.95, alpha: 1.0)
        }
    }()

//	static let keyNormalColour: UIColor = .white
    static let keyNormalColour: UIColor = .clear
    
	static let keyPressedColour: UIColor = .lightText
    
//    static let specialKeyNormalColour: UIColor = UIColor(white: 0.85, alpha: 1.0)
    static let specialKeyNormalColour: UIColor = .clear
    
    // Radial Menu Colors
    static let radialMenuSelected: CGColor = UIColor.systemBlue.withAlphaComponent(0.95).cgColor
    static let radialMenuUnselected: CGColor = UIColor.lightText.withAlphaComponent(0.9).cgColor

	static let letterKeys = [
		["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], 
		["a", "s", "d", "f", "g","h", "j", "k", "l"],
		["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
		["123", "dấu cách", "⏎"]
	]
	static let numberKeys = [
		["1", "2", "3", "4", "5", "6", "7", "8", "9", "0",],
		["-", "/", ":", ";", "(", ")" ,",", "$", "&", "@", "\""],
		["#+=",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "dấu cách", "⏎"]
	]
	
	static let symbolKeys = [
		["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
		["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
		["123",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "dấu cách", "⏎"]
	]
    static let specialKeys = ["⇧", "⌫", "#+=", "ABC", "123", "⏎"]
    
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
