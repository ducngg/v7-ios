//
//  Constants.swift
//
//  Created by Ethan Sarif-Kattan on 10/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//  Extended by Duc
//

import Foundation
import UIKit

enum Constants {
    static let haveDD = true // enable "đ"
    static let MAX_SEQUENCE_LEN = 32
    static let VOCAB_SIZE = 21869
    static let MODEL = "v7gpt-2.1-small-20250903-fp16"
    static let DEFAULT_CONTEXT = "bây giờ"
    static let TOP_K = 16
    static let MAX_FILTER_ITERATE = 2048
    static let MAX_FILTER_ITERATE_VIET = 21869 // 16384 // For rare words to be findable
    
    static let EXTRA_SUGGESTION_STEP: Int = 16
    static let EXTRA_SUGGESTION_MAX: Int = 64
    
    static let TEMPERATURE: Float = 1.0
    static let BIAS_ALPHA: Float = 0.3
    static let BIAS_INCREMENT_STEP: Float = 50 / Float(VOCAB_SIZE)
    
    static let RADIAL_MENU_MOVEMENT_MIN_THRESHOLD_TO_SHOW: CGFloat = 5.0
    static let RADIAL_MENU_MOVEMENT_MAX_THRESHOLD_TO_SHOW: CGFloat = 150.0
    
    static func keyboardHeight(isLandscape: Bool) -> CGFloat {
        return isLandscape ? 140 : 230
    }
    static func suggestionBarHeight(isLandscape: Bool) -> CGFloat {
        return isLandscape ? 30 : 40
    }

    static let fakeClear: UIColor = UIColor(white: 0.01, alpha: 0.01) // If using clear then very hard to press button
    // Using UIColor(dynamicProvider:) allows the color to automatically resolve
    // based on the trait collection of the view it is applied to.
    static let textColor: UIColor = UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return .white
        } else {
            return .black
        }
    }
    
    static let backgroundColor: UIColor = UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return fakeClear
        } else {
            return fakeClear
//            return UIColor(white: 0.85, alpha: 0.25)
        }
    }
        
    static let keyNormalColour: UIColor = UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return fakeClear
        } else {
            return fakeClear
//            return UIColor(white: 1.0, alpha: 1.0)
        }
    }
        
    static let keyPressedColour: UIColor = UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(white: 0.85, alpha: 0.2)
        } else {
            return UIColor(white: 0.45, alpha: 0.4)
//            return UIColor(white: 0.55, alpha: 0.8)
        }
    }
        
    static let specialKeyNormalColour: UIColor = UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return fakeClear
        } else {
            return fakeClear
//            return UIColor(white: 0.7, alpha: 1.0)
        }
    }
        
    // Radial Menu Colors
    static let radialMenuSelected: CGColor = UIColor.systemBlue.withAlphaComponent(0.95).cgColor
        
    // Since this must be a CGColor, we must use a computed property that
    // re-evaluates the UIColor's dynamic provider every time it is accessed.
    static var radialMenuUnselected: CGColor {
        // Define the UIColor dynamically
        let dynamicUIColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(white: 0.1, alpha: 0.94)
            } else {
                return UIColor(white: 0.9, alpha: 0.94)
            }
        }
        // Accessing the .cgColor property on a dynamic UIColor forces it to resolve
        // based on the *current* trait collection of the context where it is called.
        return dynamicUIColor.cgColor
    }
        
    // MARK: - Non-Color Constants
    
    // Use a static computed property (`var`) for the default tone display
    // so that it checks the current trait collection on every access.
    //
    // WARNING: For keyboard extensions, this still relies on UITraitCollection.current,
    // which may not always be the correct trait collection. For reliability,
    // consider passing the view's trait collection to a static function.
    //    static let defaultToneDisplay: String = "♥︎" // for love
        static let defaultToneDisplay: String = "ᯅ" // Apple vision
//        static let defaultToneDisplay: String = "⎈︎" // Helm - RadialMenu
//    static var defaultToneDisplay: String {
//        if UITraitCollection.current.userInterfaceStyle == .light {
//            return "L"
//        } else if UITraitCollection.current.userInterfaceStyle == .dark {
//            return "D"
//        } else {
//            return "U" // Unspecified
//        }
//    }

	static let letterKeys = haveDD ? [
		["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
		["a", "s", "d", "đ", "f", "g", "h", "j", "k", "l"],
		["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
		["123", "☻", "dấu cách", "⏎"]
    ] : [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
        ["123", "☻", "dấu cách", "⏎"]
    ]
	static let numberKeys = [
		["1", "2", "3", "4", "5", "6", "7", "8", "9", "0",],
		["-", "/", ":", ";", "(", ")" , "$", "&", "@", "\""],
		["#+=",".", ",", "?", "!", "\'", "⌫"],
		["ABC", "☻", "dấu cách", "⏎"]
	]
	
	static let symbolKeys = [
		["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
		["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "đ"],
		["123","·", ",", "?", "!", "\'", "⌫"],
		["ABC", "☻", "dấu cách", "⏎"]
	]
    static let specialKeys = ["⇧", "⌫", "#+=", "☻", "⏎"]
    
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
        keys.insert("đ")
        return keys
    }()
}
