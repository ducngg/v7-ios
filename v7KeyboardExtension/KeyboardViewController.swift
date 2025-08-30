//
//  KeyboardViewController.swift
//
//  Created by Ethan Sarif-Kattan on 09/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//

import UIKit
import CoreML

func model_predict(model: v7gpt_2_1_large_20250827_fp16, input: MLMultiArray) -> [Int]? {
    do {
        let output = try model.prediction(input_token_ids: input)
        return output.ranked_desc_token_idsShapedArray.scalars.map { Int($0) }
    } catch {
        keyboardLogger.error("Prediction error: \(error.localizedDescription)")
        return nil
    }
}


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
    
    let gptTokenizer = GPTTokenizer()

    // Lazily load Core ML model to avoid memory issues at startup
    lazy var model: v7gpt_2_1_large_20250827_fp16? = {
        let config = MLModelConfiguration()
//        config.computeUnits = .cpuAndNeuralEngine   // avoids GPU memory overhead
        config.computeUnits = .cpuOnly
//        config.computeUnits = .cpuAndGPU
        config.allowLowPrecisionAccumulationOnGPU = true
        
        do {
            return try v7gpt_2_1_large_20250827_fp16(configuration: config)
        } catch {
            keyboardLogger.error("⚠️ Failed to load model: \(error.localizedDescription)")
            return nil
        }
    }()
    
    let defaultContext: String = "bây giờ"
    var lastInputArray: MLMultiArray?
    
    var toneInfoLabel: UILabel?
    var currentTone: String = "" {
        didSet {
            toneInfoLabel?.text = currentTone.isEmpty ? "–" : currentTone
        }
    }

    var currentPrediction: [Int] = []
    var pattern: String = ""

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
//        NSLog("%0.4f", CGFloat.pi)

        super.viewDidLoad()
        proxy = textDocumentProxy as UITextDocumentProxy

        setupSuggestionBar()
        loadInterface()

        self.nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
        
        updatePattern()
        predict()
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

//    override func viewWillLayoutSubviews() {
//        super.viewWillLayoutSubviews()
//        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
//    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateNextKeyboardVisibility()
    }

    func updateNextKeyboardVisibility() {
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
    }

    
    func setupSuggestionBar() {
        if suggestionBar != nil { return }

        let container = UIStackView()
        container.axis = .horizontal
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        // 🔹 Fixed info label
        let infoLabel = UILabel()
        infoLabel.text = "–"   // Default when no tone selected
        infoLabel.textAlignment = .center
        infoLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        infoLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        container.addArrangedSubview(infoLabel)
        self.toneInfoLabel = infoLabel

        // 🔹 Scroll view for suggestions
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        container.addArrangedSubview(scrollView)

        // 🔹 Stack view inside scroll view
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.distribution = .fill
        bar.spacing = 8
        bar.alignment = .center
        bar.isLayoutMarginsRelativeArrangement = true
        bar.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        bar.translatesAutoresizingMaskIntoConstraints = false
        suggestionBar = bar
        scrollView.addSubview(bar)

        // 🔹 Constraints
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: 40),

            scrollView.heightAnchor.constraint(equalTo: container.heightAnchor),

            bar.topAnchor.constraint(equalTo: scrollView.topAnchor),
            bar.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            bar.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    func updateSuggestions() {
        keyboardLogger.debug("sug")

        // Clear previous buttons
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let tokenizer = self.gptTokenizer else { return }

        // 🟦 Filter predictions based on pattern + tone
        let filtered = tokenizer.filter(
            pattern: pattern,
            predictions: currentPrediction,
            toneMark: currentTone
        )

        // 🟦 Show only top-k suggestions
        for word in filtered.prefix(Constants.TOP_K) {
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

        // 🔸 Delete current pattern
        for _ in 0..<pattern.count {
            deleteBackwardAndTriggerChange()
        }

        // 🔸 Insert selected word + space
        insertTextAndTriggerChange(word + " ")
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    
    func emitTopPrediction() {
        guard let firstButton = suggestionBar?.arrangedSubviews.first as? UIButton else { return }

        // Trigger the same logic as a user tap
        didTapSuggestion(firstButton)
    }
    
    // Currently take last char
    func updatePattern() {
        let context = (proxy.documentContextBeforeInput ?? "")
            .replacingOccurrences(of: "\n", with: " ")

        if let lastChar = context.last, lastChar != " " {
            pattern = String(lastChar)
        } else {
            pattern = ""
        }
    }

    func predict() {
        // Full cleaned input
        let fullInput = (proxy.documentContextBeforeInput ?? "")
            .replacingOccurrences(of: "\n", with: " ")

        // Get context before the current pattern
        let rawContextWithoutPattern: String
        if pattern.isEmpty || fullInput.hasSuffix(" ") {
            rawContextWithoutPattern = fullInput
        } else if fullInput.hasSuffix(pattern) {
            // If fullInput ends with the pattern, drop it
            rawContextWithoutPattern = String(fullInput.dropLast(pattern.count))
        } else if let range = fullInput.range(of: pattern, options: .backwards) {
            rawContextWithoutPattern = String(fullInput[..<range.lowerBound])
        } else {
            rawContextWithoutPattern = fullInput
        }
        keyboardLogger.debug("full=[\(fullInput, privacy: .public)] rawContextWithoutPattern=[\(rawContextWithoutPattern, privacy: .public)] ")

        guard let tokenizer = self.gptTokenizer else {
            keyboardLogger.debug("❌ gptTokenizer is nil")
            return
        }
        var inputArray = tokenizer.tokenize(text: rawContextWithoutPattern)

        if inputArray.count == 0 || rawContextWithoutPattern.trimmingCharacters(in: .whitespaces).isEmpty {
            inputArray = tokenizer.tokenize(text: self.defaultContext)
        }

        if tokenizer.isSameInput(inputArray, lastInputArray) {
            self.updateSuggestions()
            return
        }

        lastInputArray = inputArray
        keyboardLogger.debug("preding")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let model = self.model else {
                keyboardLogger.error("Model is nil")
                return
            }

            let start = DispatchTime.now()

            if let predictions = model_predict(model: model, input: inputArray) {
                let end = DispatchTime.now()
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
                let timeInMs = Double(nanoTime) / 1_000_000.0
                keyboardLogger.debug("Prediction time: \(timeInMs, privacy: .public) ms")

                DispatchQueue.main.async {
                    self.currentPrediction = predictions
                    self.updateSuggestions()
                    keyboardLogger.debug("pred done")
                }
            } else {
                keyboardLogger.error("Prediction failed")
            }
        }
    }
    
    var radialMenu: RadialMenuView?
    var radialKeyButton: UIButton?

    @objc func handleKeyPan(_ gesture: UIPanGestureRecognizer) {
        guard let keyButton = gesture.view as? UIButton,
              let keyChar = keyButton.accessibilityLabel,
              let parentView = view else { return }

        radialKeyButton = keyButton
        let keyFrameInView = keyButton.superview?.convert(keyButton.frame, to: parentView) ?? .zero

        switch gesture.state {
        case .began:
            showRadialMenu(at: CGPoint(x: keyFrameInView.midX, y: keyFrameInView.midY))

        case .changed:
            let touchInRadial = gesture.location(in: radialMenu)
            radialMenu?.updateSelection(from: touchInRadial)

        case .ended, .cancelled:
            var term = keyChar
            if let selectedTone = radialMenu?.selectedTone {
                term = "\(keyChar)"
                currentTone = selectedTone   // 🔹 updates label automatically
            }

            if pattern != "" {
                self.emitTopPrediction()
            }
            keyboardLogger.debug("\(term, privacy: .public) \(self.currentTone, privacy: .public)")
            insertTextAndTriggerChange(term)

            radialMenu?.removeFromSuperview()
            radialMenu = nil
            radialKeyButton = nil

        default:
            break
        }
    }

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
            keyboardLogger.debug("Selected option: \(selected)")
            insertTextAndTriggerChange(String(selected))
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
                
                // ✅ Only add pan gesture if key is in a–z
                if Constants.allowedRadialKeys.contains(key.lowercased()) {
                    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleKeyPan(_:)))
                    button.addGestureRecognizer(panGesture)
                }
                button.accessibilityLabel = key  // for identifying the key

				let capsKey = keyboard[row][col].capitalized
				let keyToDisplay = shiftButtonState == .normal ? key : capsKey
				button.layer.setValue(key, forKey: "original")
				button.layer.setValue(keyToDisplay, forKey: "keyToDisplay")
				button.layer.setValue(false, forKey: "isSpecial")
				button.setTitle(keyToDisplay, for: .normal)
				button.layer.borderColor = keyboardView.backgroundColor?.cgColor 
                button.layer.borderWidth = 3
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
        // More logic here
        deleteBackwardAndTriggerChange()
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
                insertTextAndTriggerChange(" ")
            case "🌐":
                break
            case "⏎":
                insertTextAndTriggerChange("\n")
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
                insertTextAndTriggerChange(keyToDisplay)
		}
        currentTone = ""
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
    
    func insertTextAndTriggerChange(_ text: String) {
        proxy.insertText(text)
        self.textDidChange(nil)
    }

    func deleteBackwardAndTriggerChange() {
        proxy.deleteBackward()
        self.textDidChange(nil)
    }

	
	override func textDidChange(_ textInput: UITextInput?) {
		// The app has just changed the document's contents, the document context has been updated.
//		log("tdc")
		var textColor: UIColor
		let proxy = self.textDocumentProxy
		if proxy.keyboardAppearance == UIKeyboardAppearance.dark {
			textColor = UIColor.white
		} else {
			textColor = UIColor.black
		}
		self.nextKeyboardButton.setTitleColor(textColor, for: [])
        
        self.updatePattern()
        self.predict()
    }
}
