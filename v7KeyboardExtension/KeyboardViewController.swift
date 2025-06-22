//
//  KeyboardViewController.swift
//
//  Created by Ethan Sarif-Kattan on 09/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//

import UIKit

extension UILabel {
    func padding(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let insets = UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        drawText(in: bounds.inset(by: insets))
    }
}

var proxy : UITextDocumentProxy!

class RadialMenuView: UIView {
    var selectedIndex: Int? = nil
    var selectedTone: String? = nil

    let tone_diacritics = ["◌́", "◌", "◌̀", "◌̣", "◌̃", "◌̉"]
    let numberOfSectors = 6
    let angleOffset: CGFloat = -.pi / 2  // Rotate start to top (90° CCW)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false  // pure visual
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2

        let font = UIFont.systemFont(ofSize: 14)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.black,
            .font: font
        ]

        for i in 0..<numberOfSectors {
            let startAngle = CGFloat(i) * .pi * 2 / CGFloat(numberOfSectors) + angleOffset
            let endAngle = CGFloat(i + 1) * .pi * 2 / CGFloat(numberOfSectors) + angleOffset

            // Draw the sector
            ctx.setFillColor((i == selectedIndex) ? UIColor.systemBlue.cgColor : Constants.keyNormalColour.cgColor)
            ctx.move(to: center)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.fillPath()

            // Draw the number in the center of the sector
            let angle = startAngle + (endAngle - startAngle) / 2
            let labelCenter = CGPoint(x: center.x + cos(angle) * (radius - 20), y: center.y + sin(angle) * (radius - 20))

            let number = tone_diacritics[i]
            let textSize = (number as NSString).size(withAttributes: textAttributes)
            let textRect = CGRect(x: labelCenter.x - textSize.width / 2, y: labelCenter.y - textSize.height / 2, width: textSize.width, height: textSize.height)

            number.draw(in: textRect, withAttributes: textAttributes)
        }
    }

    func updateSelection(from touch: CGPoint) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = touch.x - center.x
        let dy = touch.y - center.y
        
        let angle = atan2(dy, dx)
        let positiveAngle = (angle >= 0 ? angle : angle + 2 * .pi)
        
        let adjustedAngle = positiveAngle - angleOffset
        let index = Int(adjustedAngle / (2 * .pi) * CGFloat(numberOfSectors)) % numberOfSectors

        selectedIndex = index
        if let index = selectedIndex {
            selectedTone = tone_diacritics[index]
        }
        setNeedsDisplay()
    }
}


class KeyboardViewController: UIInputViewController {
	
	@IBOutlet var nextKeyboardButton: UIButton!
	
    var suggestionBar: UIStackView?
	var keyboardView: UIView!
	var keys: [UIButton] = []
	var paddingViews: [UIButton] = []
	var backspaceTimer: Timer?
    
    let gptModel = GPTModel(modelName: Constants.MODEL)
    var context: [String] = ["bây", "giờ"]
    var buffer: [[String]] = []
    var cumulated_terms: String = ""
    var current_term: String = ""

	enum KeyboardState{
		case letters
		case numbers
		case symbols
	}
	
	enum ShiftButtonState {
		case normal
		case shift
		case caps
	}
	
	var keyboardState: KeyboardState = .letters
	var shiftButtonState:ShiftButtonState = .normal
    var hasEnteredRadialMenu = false

	
	@IBOutlet weak var stackView1: UIStackView!
	@IBOutlet weak var stackView2: UIStackView!
	@IBOutlet weak var stackView3: UIStackView!
	@IBOutlet weak var stackView4: UIStackView!
	
	
    override func updateViewConstraints() {
        super.updateViewConstraints()
        keyboardView.frame.size = view.frame.size
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        proxy = textDocumentProxy as UITextDocumentProxy

        setupSuggestionBar()
        loadInterface()

        self.nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let heightConstraint = NSLayoutConstraint(
            item: view!,
            attribute: .height,
            relatedBy: .equal,
            toItem: nil,
            attribute: .notAnAttribute,
            multiplier: 1.0,
            constant: 260 // 220 keyboard + 40 suggestion bar
        )
        view.addConstraint(heightConstraint)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
    }
    
    func setupSuggestionBar() {
        if suggestionBar != nil { return }

        // Create a scroll view to contain the stack view
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false  // Hide scroll indicator
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        view.addSubview(scrollView)

        // Create the stack view inside the scroll view
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.backgroundColor = .clear  // Transparent background
        bar.distribution = .fill
        bar.spacing = 8
        bar.alignment = .center
        bar.isLayoutMarginsRelativeArrangement = true
        bar.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)  // Adjust padding to fit the keyboard
        bar.translatesAutoresizingMaskIntoConstraints = false
        suggestionBar = bar
        scrollView.addSubview(bar)

        // Add constraints for the scroll view and stack view
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            scrollView.heightAnchor.constraint(equalToConstant: 40),

            // Stack view constraints inside the scroll view
            bar.topAnchor.constraint(equalTo: scrollView.topAnchor),
            bar.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            bar.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    func updateSuggestions(_ suggestions: [String]) {
        // Clear previous buttons
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 🟦 Show buffer as one joined label from predictions[0]
        let bufferText = buffer.dropLast().map { $0[0] }.joined(separator: " ")
        if !bufferText.isEmpty {
            let label = UILabel()
            label.text = bufferText
            label.font = UIFont.systemFont(ofSize: 16, weight: .light)
            label.textColor = .gray
            label.backgroundColor = .clear
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            label.textAlignment = .center
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
//            label.layer.borderColor = UIColor.gray.cgColor
//            label.layer.borderWidth = 0.5
            label.padding(left: 12, right: 12, top: 4, bottom: 4)
            suggestionBar?.addArrangedSubview(label)
        }

        // 🟦 Show tappable suggestions
        for word in suggestions {
            let button = UIButton(type: .system)
            button.setTitle(word, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .regular)
            button.setTitleColor(.black, for: .normal)
            button.backgroundColor = .clear
            button.layer.cornerRadius = 6
            button.addTarget(self, action: #selector(didTapSuggestion(_:)), for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            suggestionBar?.addArrangedSubview(button)
        }

        suggestionBar?.invalidateIntrinsicContentSize()
    }


    @objc func didTapSuggestion(_ sender: UIButton) {
        guard let word = sender.title(for: .normal) else { return }

        // Step 1: Remove current text
        for _ in 0..<cumulated_terms.count {
            proxy.deleteBackward()
        }

        // Step 2: Insert all buffer words and the selected one
        let allWords = buffer.dropLast().compactMap { $0.first } + [word]
        let fullText = allWords.joined(separator: " ") + " "
        proxy.insertText(fullText)

        // Step 3: Update context
        context.append(contentsOf: allWords)

        // Step 4: Reset state
        buffer.removeAll()
        current_term = ""
        cumulated_terms = ""
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }


    func predict(for input: String) {
//        let rawContext = proxy.documentContextBeforeInput ?? "tôi"
//
//        let contextWords = rawContext.split(separator: " ")
//        let trimmedContext = contextWords.suffix(32).joined(separator: " ")
//        
        let joinedContext = (context + buffer.compactMap { $0.first })
            .suffix(32).joined(separator: " ")
//        proxy.insertText(joinedContext)

        DispatchQueue.global(qos: .userInitiated).async {
            guard let model = self.gptModel else { return }
            let predictions = model.predict(raw: input, context: joinedContext)

            DispatchQueue.main.async {
                self.updateSuggestions(predictions)
            }
            self.buffer.append(predictions)
        }
    }


    
    let variantCharacters: [String: [String]] = [
        "d": ["d", "đ"],
        "k": ["k", "kh"],
        "n": ["nh", "n", "ng"],
        "c": ["c", "ch"],
        "t": ["tr", "t", "th"],
    ]
    let radialOnlyKeys: Set<String> = [
        "q", "e", "r", "y", "u", "i", "o", "p",
        "a", "s", "f", "g", "h", "l",
        "z", "x", "v", "b", "m",
    ]  // Customize your keys here

    var variantKeyButton: UIButton?  // currently touched key with variant
    var variantOptionBox: UIView?
    var selectedVariantButton: UIButton?
    var radialMenu: RadialMenuView?

    func showVariantBox(variants: [String], over keyFrame: CGRect) {
        if variantOptionBox == nil {
            variantOptionBox = UIView()
            variantOptionBox?.backgroundColor = Constants.keyNormalColour
            variantOptionBox?.layer.cornerRadius = 8
            view.addSubview(variantOptionBox!)
        }

        // Clean old buttons
        variantOptionBox?.subviews.forEach { $0.removeFromSuperview() }

        let btnWidth: CGFloat = 50
        let spacing: CGFloat = 10
        let totalWidth = CGFloat(variants.count) * btnWidth + CGFloat(variants.count - 1) * spacing
        let boxHeight: CGFloat = 40

        // 🆙 Place the box slightly above the key
        let boxX = keyFrame.midX - totalWidth / 2
        var boxY = keyFrame.minY + (boxHeight / 2)
        if variantKeyButton?.accessibilityLabel == "t" {
            // ⬇️ Show below the key
            boxY = keyFrame.minY + (boxHeight / 2)
        }

        variantOptionBox?.frame = CGRect(x: boxX, y: boxY, width: totalWidth, height: boxHeight)
        variantOptionBox?.isHidden = false

        for (i, v) in variants.enumerated() {
            let button = UIButton(type: .custom)
            button.setTitle(v, for: .normal)
            button.frame = CGRect(x: CGFloat(i) * (btnWidth + spacing), y: 5, width: btnWidth, height: 30)
            button.backgroundColor = Constants.keyNormalColour
            button.setTitleColor(.black, for: .normal)
            variantOptionBox?.addSubview(button)
        }
    }


    @objc func handleVariantPan(_ gesture: UIPanGestureRecognizer) {
        guard let keyButton = gesture.view as? UIButton,
              let keyChar = keyButton.accessibilityLabel,
              let parentView = view else { return }

        variantKeyButton = keyButton
        let keyFrameInView = keyButton.superview?.convert(keyButton.frame, to: parentView) ?? .zero
        let variants = variantCharacters[keyChar]  // may be nil
        let shouldShowRadialOnly = radialOnlyKeys.contains(keyChar)

        switch gesture.state {
        case .began:
            hasEnteredRadialMenu = false
            
            if let variants = variants {
                showVariantBox(variants: variants, over: keyFrameInView)
            } else if shouldShowRadialOnly {
                showRadialMenu(at: CGPoint(x: keyFrameInView.midX, y: keyFrameInView.midY))
            }

        case .changed:
            if let variants = variants {
                let touchInBox = gesture.location(in: variantOptionBox)

                // Only allow variant selection if NOT already dragging in radial menu
                if !hasEnteredRadialMenu {
                    for case let btn as UIButton in variantOptionBox?.subviews ?? [] {
                        if btn.frame.contains(touchInBox) {
                            highlightVariantButton(btn)

                            if radialMenu?.superview == nil {
                                let btnFrameInParent = btn.superview?.convert(btn.frame, to: parentView) ?? .zero
                                showRadialMenu(at: CGPoint(x: btnFrameInParent.midX, y: btnFrameInParent.midY))
                            }

                            break
                        }
                    }
                }

                // ✅ Always update radial menu if it's visible
                if radialMenu?.superview != nil {
                    let touchInRadial = gesture.location(in: radialMenu)
                    radialMenu?.updateSelection(from: touchInRadial)
                    
                    // ✅ Lock variant when entering radial
                    if radialMenu!.bounds.contains(touchInRadial) {
                        hasEnteredRadialMenu = true
                    }
                }
                
            } else if shouldShowRadialOnly {
                if radialMenu == nil {
                    showRadialMenu(at: CGPoint(x: keyFrameInView.midX, y: keyFrameInView.midY))
                }

                let touchInRadial = gesture.location(in: radialMenu)
                radialMenu?.updateSelection(from: touchInRadial)
            }

        case .ended, .cancelled:
            if let selectedTone = radialMenu?.selectedTone {
                if let selected = selectedVariantButton {
                    let variant = selected.title(for: .normal) ?? ""
                    cumulated_terms += "\(variant)\(selectedTone)"
                    current_term = "\(variant)\(selectedTone)"
                } else {
                    cumulated_terms += "\(keyChar)\(selectedTone)"
                    current_term = "\(keyChar)\(selectedTone)"
                }
                proxy.insertText(current_term)
                predict(for: current_term)
            } else if let selected = selectedVariantButton {
                proxy.insertText(selected.title(for: .normal) ?? "")
            }

            variantOptionBox?.isHidden = true
            selectedVariantButton = nil
            variantKeyButton = nil
            radialMenu?.removeFromSuperview()
            radialMenu = nil

        default:
            break
        }
    }


    func highlightVariantButton(_ button: UIButton) {
        if selectedVariantButton != button {
            for case let btn as UIButton in variantOptionBox?.subviews ?? [] {
                btn.backgroundColor = .clear
            }
            button.backgroundColor = .blue
            selectedVariantButton = button
        }
    }
    
    //
    
    func showRadialMenu(at center: CGPoint) {
        if radialMenu == nil {
            radialMenu = RadialMenuView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
            view.addSubview(radialMenu!)
        }

        radialMenu?.center = center
        radialMenu?.isHidden = false
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: radialMenu)

        radialMenu?.updateSelection(from: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let selected = radialMenu?.selectedIndex {
            print("Selected option: \(selected)")
            proxy.insertText(String(selected))
            // You can now trigger the action for that index (0-5)
        }

        radialMenu?.removeFromSuperview()
        radialMenu = nil
    }

	
    //
	
//	func loadInterface(){
//		let keyboardNib = UINib(nibName: "Keyboard", bundle: nil)
//		keyboardView = keyboardNib.instantiate(withOwner: self, options: nil)[0] as? UIView
//        setupSuggestionBar()
//		view.addSubview(keyboardView)
//        loadKeys()
//	}
    
    func loadInterface() {
        let keyboardNib = UINib(nibName: "Keyboard", bundle: nil)
        keyboardView = keyboardNib.instantiate(withOwner: self, options: nil)[0] as? UIView
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            keyboardView.topAnchor.constraint(equalTo: suggestionBar?.bottomAnchor ?? view.topAnchor, constant: 4),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        loadKeys()
    }
	
	func addPadding(to stackView: UIStackView, width: CGFloat, key: String){
		let padding = UIButton(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
		padding.setTitleColor(.clear, for: .normal)
		padding.alpha = 0.02
		padding.widthAnchor.constraint(equalToConstant: width).isActive = true
		
		//if we want to use this padding as a key, for example the a and l buttons
		let keyToDisplay = shiftButtonState == .normal ? key : key.capitalized
		padding.layer.setValue(key, forKey: "original")
		padding.layer.setValue(keyToDisplay, forKey: "keyToDisplay")
		padding.layer.setValue(false, forKey: "isSpecial")
		padding.addTarget(self, action: #selector(keyPressedTouchUp), for: .touchUpInside)
		padding.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)
		padding.addTarget(self, action: #selector(keyUntouched), for: .touchDragExit)
		
		paddingViews.append(padding)
		stackView.addArrangedSubview(padding)
	}
	
	func loadKeys(){
		keys.forEach{$0.removeFromSuperview()}
		paddingViews.forEach{$0.removeFromSuperview()}
		
        let maxKeyCount = (Constants.letterKeys.map { $0.count }.max() ?? 10) + 1
        let buttonWidth = (UIScreen.main.bounds.width - 6) / CGFloat(maxKeyCount)
//		let buttonWidth = (UIScreen.main.bounds.width - 6) / CGFloat(Constants.letterKeys[0].count)
		
		var keyboard: [[String]]
		
		//start padding
		switch keyboardState {
		case .letters:
			keyboard = Constants.letterKeys
            addPadding(to: stackView1, width: buttonWidth/2, key: "")
            addPadding(to: stackView2, width: buttonWidth/2, key: "")
            addPadding(to: stackView3, width: buttonWidth/2, key: "")
            addPadding(to: stackView4, width: buttonWidth/2, key: "")

            // Extra
			addPadding(to: stackView2, width: buttonWidth/2, key: "")
            
            
		case .numbers:
			keyboard = Constants.numberKeys
		case .symbols: 
			keyboard = Constants.symbolKeys
		}
		
		let numRows = keyboard.count
		for row in 0...numRows - 1{
			for col in 0...keyboard[row].count - 1{
				let button = UIButton(type: .custom)
				button.backgroundColor = Constants.keyNormalColour
				button.setTitleColor(.black, for: .normal) 
				let key = keyboard[row][col]
                
                let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleVariantPan(_:)))
                button.addGestureRecognizer(panGesture)
                button.accessibilityLabel = key  // for identifying the key

				let capsKey = keyboard[row][col].capitalized
				let keyToDisplay = shiftButtonState == .normal ? key : capsKey
				button.layer.setValue(key, forKey: "original")
				button.layer.setValue(keyToDisplay, forKey: "keyToDisplay")
				button.layer.setValue(false, forKey: "isSpecial")
				button.setTitle(keyToDisplay, for: .normal)
				button.layer.borderColor = keyboardView.backgroundColor?.cgColor 
				button.layer.borderWidth = 4
				button.addTarget(self, action: #selector(keyPressedTouchUp), for: .touchUpInside)
				button.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)
				button.addTarget(self, action: #selector(keyUntouched), for: .touchDragExit)
				button.addTarget(self, action: #selector(keyMultiPress(_:event:)), for: .touchDownRepeat)

				if key == "⌫"{
					let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(keyLongPressed(_:)))
					button.addGestureRecognizer(longPressRecognizer)
				}				
				
				button.layer.cornerRadius = buttonWidth/4
				keys.append(button)
				switch row{
				case 0: stackView1.addArrangedSubview(button)
				case 1: stackView2.addArrangedSubview(button)
				case 2: stackView3.addArrangedSubview(button)
				case 3: stackView4.addArrangedSubview(button)
				default:
					break
				}
				if key == "🌐"{
					nextKeyboardButton = button
				}
				
				//top row is longest row so it should decide button width 
				print("button width: ", buttonWidth)
				if key == "⌫" || key == "⏎" || key == "#+=" || key == "ABC" || key == "123" || key == "⇧" || key == "🌐"{
					button.widthAnchor.constraint(equalToConstant: buttonWidth + buttonWidth/2).isActive = true
					button.layer.setValue(true, forKey: "isSpecial")
					button.backgroundColor = Constants.specialKeyNormalColour
					if key == "⇧" {
						if shiftButtonState != .normal{
							button.backgroundColor = Constants.keyPressedColour
						}
						if shiftButtonState == .caps{
							button.setTitle("⏫", for: .normal)
						}
					}
				}else if (keyboardState == .numbers || keyboardState == .symbols) && row == 2{
					button.widthAnchor.constraint(equalToConstant: buttonWidth * 1.4).isActive = true
				}else if key != "dấu cách"{
					button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
				}else{
					button.layer.setValue(key, forKey: "original")
					button.setTitle(key, for: .normal)
				}
			}
		} 
		
		
		//end padding
		switch keyboardState {
            case .letters:
                // Extra
                addPadding(to: stackView2, width: buttonWidth/2, key: "")
            
                addPadding(to: stackView1, width: buttonWidth/2, key: "")
                addPadding(to: stackView2, width: buttonWidth/2, key: "")
                addPadding(to: stackView3, width: buttonWidth/2, key: "")
                addPadding(to: stackView4, width: buttonWidth/2, key: "")

            case .numbers:
                break
            case .symbols: break
		}
		
	}
		
	func changeKeyboardToNumberKeys(){
		keyboardState = .numbers
		shiftButtonState = .normal
		loadKeys()
	}
	func changeKeyboardToLetterKeys(){
		keyboardState = .letters
		loadKeys()
	}
	func changeKeyboardToSymbolKeys(){
		keyboardState = .symbols
		loadKeys()
	}
    func handleDeleteButtonPressed() {
        guard !cumulated_terms.isEmpty else {
            proxy.deleteBackward()  // fallback if nothing to remove
            return
        }

        // 🔸 Delete each character in current_term from the input field
        for _ in 0..<current_term.count {
            proxy.deleteBackward()
        }

        // 🔸 Trim cumulated_terms by current_term + space
        if cumulated_terms.hasSuffix(current_term) {
            cumulated_terms.removeLast(current_term.count)
        }

        // 🔸 Remove last prediction from buffer
        if !buffer.isEmpty {
            buffer.removeLast()
        }

        // 🔸 Update current_term
        // Find the second-to-last tone character and update current_term
        let secondToneIndex = findSecondToneIndex()
        
        // If there's a valid second tone index, set current_term to the next term
        if let secondToneRange = secondToneIndex {
            let newStartIndex = cumulated_terms.index(secondToneRange, offsetBy: 1) // Start after second tone
            current_term = String(cumulated_terms[newStartIndex...])  // New current_term
        } else {
            current_term = cumulated_terms  // Default value if no second tone is found
        }
        
        // 🔸 Update suggestion bar
        let predictions = buffer.last ?? []
        updateSuggestions(predictions)
    }
    
    func findSecondToneIndex() -> String.Index? {
        let toneCharacters: Set<Character> = ["◌", "◌́", "◌̀", "◌̣", "◌̃", "◌̉"]
        var toneIndices = [String.Index]()

        // Find all tone characters in reverse order
        for index in cumulated_terms.indices.reversed() {
            let char = cumulated_terms[index]
            if toneCharacters.contains(char) {
                toneIndices.append(index)
                if toneIndices.count == 2 {
                    break
                }
            }
        }

        // Return the second tone index, if found
        return toneIndices.count >= 2 ? toneIndices[1] : nil
    }

	
	@IBAction func keyPressedTouchUp(_ sender: UIButton) {
		guard let originalKey = sender.layer.value(forKey: "original") as? String, let keyToDisplay = sender.layer.value(forKey: "keyToDisplay") as? String else {return}
		
		guard let isSpecial = sender.layer.value(forKey: "isSpecial") as? Bool else {return}
		sender.backgroundColor = isSpecial ? Constants.specialKeyNormalColour : Constants.keyNormalColour

		switch originalKey {
		case "⌫":
			if shiftButtonState == .shift {
				shiftButtonState = .normal
				loadKeys()
			}
            handleDeleteButtonPressed()
		case "dấu cách":
			proxy.insertText(" ")
		case "🌐":
			break
		case "⏎":
			proxy.insertText("\n")
		case "123":
			changeKeyboardToNumberKeys()
		case "ABC":
			changeKeyboardToLetterKeys()
		case "#+=":
			changeKeyboardToSymbolKeys()
		case "⇧":
			shiftButtonState = shiftButtonState == .normal ? .shift : .normal
			loadKeys()
		default:
			if shiftButtonState == .shift {
				shiftButtonState = .normal
				loadKeys()
			}
			proxy.insertText(keyToDisplay)
		}
	}
	
	@objc func keyMultiPress(_ sender: UIButton, event: UIEvent){
		guard let originalKey = sender.layer.value(forKey: "original") as? String else {return}

		let touch: UITouch = event.allTouches!.first!
		if (touch.tapCount == 2 && originalKey == "⇧") {
			shiftButtonState = .caps
			loadKeys()
		}
	}	
	
	@objc func keyLongPressed(_ gesture: UIGestureRecognizer){
		if gesture.state == .began {
			backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { (timer) in
				self.handleDeleteButtonPressed()
			}
		} else if gesture.state == .ended || gesture.state == .cancelled {
			backspaceTimer?.invalidate()
			backspaceTimer = nil
			(gesture.view as! UIButton).backgroundColor = Constants.specialKeyNormalColour
		}
	}
	
	@objc func keyUntouched(_ sender: UIButton){
		guard let isSpecial = sender.layer.value(forKey: "isSpecial") as? Bool else {return}
		sender.backgroundColor = isSpecial ? Constants.specialKeyNormalColour : Constants.keyNormalColour
	}
	
	@objc func keyTouchDown(_ sender: UIButton){
		sender.backgroundColor = Constants.keyPressedColour
	}
	
	override func textWillChange(_ textInput: UITextInput?) {
		// The app is about to change the document's contents. Perform any preparation here.
	}
	
	override func textDidChange(_ textInput: UITextInput?) {
		// The app has just changed the document's contents, the document context has been updated.
		
		var textColor: UIColor
		let proxy = self.textDocumentProxy
		if proxy.keyboardAppearance == UIKeyboardAppearance.dark {
			textColor = UIColor.white
		} else {
			textColor = UIColor.black
		}
		self.nextKeyboardButton.setTitleColor(textColor, for: [])
	}
	
}
