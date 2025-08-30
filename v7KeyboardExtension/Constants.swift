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
    static let MODEL = "v7gpt-2.1-large-20250827"
    static let TOP_K = 16
    static let MAX_FILTER_ITERATE = 2048

	static let keyNormalColour: UIColor = .white
	static let keyPressedColour: UIColor = .lightText
	static let specialKeyNormalColour: UIColor = .gray

	static let letterKeys = [
		["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], 
		["a", "s", "d", "f", "g","h", "j", "k", "l"],
		["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
		["123", "🌐", "dấu cách", "⏎"]
	]
	static let numberKeys = [
		["1", "2", "3", "4", "5", "6", "7", "8", "9", "0",],
		["-", "/", ":", ";", "(", ")" ,",", "$", "&", "@", "\""],
		["#+=",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "🌐", "dấu cách", "⏎"]
	]
	
	static let symbolKeys = [
		["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
		["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
		["123",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "🌐", "dấu cách", "⏎"]
	]
    
    static let allowedRadialKeys: Set<String> = Set((97...122).map { String(UnicodeScalar($0)!) }) // "a"..."z"
}
