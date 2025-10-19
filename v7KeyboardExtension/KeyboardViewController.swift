//
//  KeyboardViewController.swift
//
//  Created by Ethan Sarif-Kattan on 09/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//  Extended by Duc
//

import UIKit
import CoreML

extension UILabel {
    func padding(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let insets = UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        drawText(in: bounds.inset(by: insets))
    }
}

var proxy : UITextDocumentProxy!

class KeyboardViewController: UIInputViewController, UIScrollViewDelegate {
		
    var suggestionBar: UIStackView?
	var keyboardView: UIView!
	var keys: [UIButton] = []
	var paddingViews: [UIButton] = []
	var backspaceTimer: Timer?
    
    let gptTokenizer = GPTTokenizer()
    var biasVectorManager: BiasVectorManager?

    var model: v7gpt_2_2_small_20250909_with_bias?
    private func loadModel() {
        autoreleasepool {
            let config = MLModelConfiguration()
            //        config.computeUnits = .cpuAndNeuralEngine   // avoids GPU memory overhead
            //        config.computeUnits = .cpuOnly
            //        config.computeUnits = .cpuAndGPU
            config.computeUnits = .cpuOnly   // ✅ safest for extensions
            do {
                let t0 = Date()
                model = try v7gpt_2_2_small_20250909_with_bias(configuration: config)
                keyboardLogger.debug("✅ Model loaded in \(Date().timeIntervalSince(t0))s")
            } catch {
                keyboardLogger.error("⚠️ Failed to load model: \(error.localizedDescription)")
            }
        }
    }
    
    let defaultContext: String = Constants.DEFAULT_CONTEXT
    var lastRawContextWithoutPattern: String?
    var lastInputArray: MLMultiArray?
    var toneInfoLabel: UILabel?
    var currentTone: String = "" {
        didSet {
            toneInfoLabel?.text = currentTone.isEmpty ? Constants.defaultToneDisplay : currentTone
        }
    }
    func resetCurrentTone() {
        currentTone = ""
    }

    var currentPrediction: [Int] = []
    var currentExtraSuggestion: Int = 0
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
    private var panStartPoint: CGPoint?   // Store where the gesture began
	
    var suggestionScrollView: UIScrollView?
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
        loadModel()
        
        let cached = CacheManager.loadCache()
        biasVectorManager = BiasVectorManager(initialVector: cached)

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
//    
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        updateNextKeyboardVisibility()
//    }
//
//    func updateNextKeyboardVisibility() {
//        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
//    }

    func setupSuggestionBar() {
        if suggestionBar != nil { return }

        let container = UIStackView()
        container.axis = .horizontal
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        view.addSubview(container)

        // 🔹 Blur background (same as keyboardView)
//        let blurEffect: UIBlurEffect
//        if traitCollection.userInterfaceStyle == .dark {
//            blurEffect = UIBlurEffect(style: .systemThinMaterialDark)
//        } else {
//            blurEffect = UIBlurEffect(style: .systemThinMaterialLight)
//        }
//
//        let blurView = UIVisualEffectView(effect: blurEffect)
//        blurView.translatesAutoresizingMaskIntoConstraints = false
//        container.insertSubview(blurView, at: 0) // background

//        NSLayoutConstraint.activate([
//            blurView.topAnchor.constraint(equalTo: container.topAnchor),
//            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
//            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
//            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
//        ])

        // 🔹 Fixed info label
        let infoLabel = UILabel()
        infoLabel.text = Constants.defaultToneDisplay
        infoLabel.textAlignment = .center
        infoLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        infoLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        infoLabel.textColor = Constants.textColor
        infoLabel.backgroundColor = Constants.backgroundColor
        container.addArrangedSubview(infoLabel)
        self.toneInfoLabel = infoLabel

        // 🔹 Scroll view for suggestions
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = Constants.backgroundColor
        scrollView.delegate = self
        container.addArrangedSubview(scrollView)
        self.suggestionScrollView = scrollView

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
    @objc func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // check if user scrolled near the right edge
        let offsetX = scrollView.contentOffset.x
        let maxOffsetX = scrollView.contentSize.width - scrollView.bounds.width
        
        // tolerance (to avoid pixel rounding issues)
        if offsetX >= maxOffsetX - 10 {
            loadMoreSuggestions()
        }
    }
    private func loadMoreSuggestions() {
        guard currentExtraSuggestion < Constants.EXTRA_SUGGESTION_MAX else { return }

        currentExtraSuggestion += Constants.EXTRA_SUGGESTION_STEP
        updateSuggestions()
        
    }


    func updateSuggestions() {
        // Clear previous buttons
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let tokenizer = self.gptTokenizer else { return }

        // 🟦 Filter predictions based on pattern + tone
        let filtered = tokenizer.filter(
            pattern: pattern,
            predictions: currentPrediction,
            toneMark: currentTone,
            extraSuggestion: currentExtraSuggestion,
        )
//        let filtered = ["Hello", pattern]

        // 🟦 Show only top-k suggestions
        for word in filtered {
            
            var adjusted = word
            if shiftButtonState == .caps {
                // 🔹 Capitalize whole word
                adjusted = word.uppercased()
            } else if shiftButtonState == .shift || (!pattern.isEmpty && pattern.first!.isUppercase) {
                // 🔹 Capitalize only first letter
                adjusted = word.prefix(1).uppercased() + word.dropFirst()
            }
        
            let button = UIButton(type: .system)
            button.setTitle(adjusted, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .regular)
            button.setTitleColor(Constants.textColor, for: .normal)
            button.backgroundColor = .clear
            button.layer.cornerRadius = 6
            button.addTarget(self, action: #selector(didTapSuggestion(_:)), for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            suggestionBar?.addArrangedSubview(button)
        }

        suggestionBar?.invalidateIntrinsicContentSize()
    }

    // Keep the @objc exposed version for button taps
    @objc func didTapSuggestion(_ sender: UIButton) {
        didTapSuggestion(sender, fromRadialMenu: false)
    }
    func didTapSuggestion(_ sender: UIButton, fromRadialMenu: Bool = false) {
        guard let word = sender.title(for: .normal) else { return }
        
        // 🔸 Delete current pattern
        for _ in 0..<pattern.count {
            deleteBackwardAndTriggerChange()
        }
        
        // 🔸 Insert selected word + space
        insertTextAndTriggerChange(word + " ")
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // 🔸 Reset tone unless it comes from radial menu
        if !fromRadialMenu {
            resetCurrentTone()
        }
        
        if shiftButtonState != .caps {
            shiftButtonState = .normal
            loadKeys()
        }
        
        // 🔸 Update cache
        guard let tokenizer = self.gptTokenizer else {
            keyboardLogger.debug("❌ gptTokenizer is nil")
            return
        }
        guard let biasVectorManager = self.biasVectorManager else {
            keyboardLogger.debug("❌ biasVectorManager is nil")
            return
        }
        if let index = tokenizer.enumDict[word.lowercased()] {
            // Update bias vector
            biasVectorManager.updateBiasVector(at: index)

            // Save updated vector to cache
            CacheManager.saveCache(biasVectorManager.biasVector)

            keyboardLogger.debug("✅ Updated bias for '\(word)' at index \(index)")
        } else {
            keyboardLogger.debug("⚠️ Token not found for '\(word)'")
        }

    }
    func emitTopPrediction() {
        guard let firstButton = suggestionBar?.arrangedSubviews.first as? UIButton else { return }
        // Trigger the same logic as a user tap
        didTapSuggestion(firstButton, fromRadialMenu: true)
    }
    
    func updatePattern() {
        let context = (proxy.documentContextBeforeInput ?? "")
            .replacingOccurrences(of: "\n", with: " ")

        if context.hasSuffix(" ") {
            // Cursor is after a space → new word starting
            pattern = ""
        } else {
            // Take the last term
            let terms = context.split(separator: " ").map(String.init)
            pattern = terms.last ?? ""
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
        
        if rawContextWithoutPattern == lastRawContextWithoutPattern{
            self.updateSuggestions()
            return
        }
        lastRawContextWithoutPattern = rawContextWithoutPattern
        
        keyboardLogger.debug("full=[\(fullInput, privacy: .public)] rawContextWithoutPattern=[\(rawContextWithoutPattern, privacy: .public)] ")

        guard let tokenizer = self.gptTokenizer else {
            keyboardLogger.debug("❌ gptTokenizer is nil")
            return
        }
        guard let biasVectorManager = self.biasVectorManager else {
            keyboardLogger.debug("❌ biasVectorManager is nil")
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

            if let predictions = model_predict(
                model: model,
                input: inputArray,
                biasVector: biasVectorManager.biasVector,
                alpha: Constants.BIAS_ALPHA,
                temperature: Constants.TEMPERATURE,
            ) {
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

        let keyFrameInView = keyButton.superview?.convert(keyButton.frame, to: parentView) ?? .zero

        switch gesture.state {
        case .began:
            radialKeyButton = keyButton
            panStartPoint = gesture.location(in: parentView)

        case .changed:
            guard let start = panStartPoint else { return }
            let current = gesture.location(in: parentView)
            let distance = hypot(current.x - start.x, current.y - start.y)

            // 🔹 Hide radial if moved too far
            if distance > Constants.RADIAL_MENU_MOVEMENT_MAX_THRESHOLD_TO_SHOW {
                radialMenu?.removeFromSuperview()
                radialMenu = nil
                return
            }

            // 🔹 Show menu only if moved enough and not too far
            if radialMenu == nil,
               distance > Constants.RADIAL_MENU_MOVEMENT_MIN_THRESHOLD_TO_SHOW {
                showRadialMenu(
                    at: CGPoint(x: keyFrameInView.midX, y: keyFrameInView.midY),
                    for: keyChar
                )
            }

            // 🔹 Update selection if already showing
            if let radialMenu = radialMenu {
                let touchInRadial = gesture.location(in: radialMenu)
                radialMenu.updateSelection(from: touchInRadial)
            }

        case .ended, .cancelled:
            let term = shiftButtonState == .normal ? keyChar : keyChar.uppercased()

            // 🔹 If menu was dismissed due to over-move, ignore
            guard let radialMenu = radialMenu else {
                if !pattern.isEmpty { emitTopPrediction() }
                insertTextAndTriggerChange(term)
                return
            }

            if let selectedItem = radialMenu.selectedItem {
                if selectedItem == "." || selectedItem == "," {
                    // Special punctuation handling
                    if !pattern.isEmpty && !currentTone.isEmpty {
                        emitTopPrediction()
                    }
                    if (proxy.documentContextBeforeInput ?? "").hasSuffix(" ") {
                        proxy.deleteBackward()
                    }
                    insertTextAndTriggerChange(selectedItem + " ")
                    resetCurrentTone()
                } else {
                    // Normal tone-mark behavior
                    currentTone = selectedItem
                    if !pattern.isEmpty {
                        emitTopPrediction()
                    }
                    insertTextAndTriggerChange(term)
                }
            } else {
                // No radial selection
                if !pattern.isEmpty { emitTopPrediction() }
                insertTextAndTriggerChange(term)
            }

            keyboardLogger.debug("\(term, privacy: .public) \(self.currentTone, privacy: .public)")

            radialMenu.removeFromSuperview()
            self.radialMenu = nil
            self.radialKeyButton = nil

            if shiftButtonState != .normal {
                shiftButtonState = shiftButtonState == .caps ? .caps : .normal
                loadKeys()
            }

            // Reset key color
            if let isSpecial = keyButton.layer.value(forKey: "isSpecial") as? Bool {
                keyButton.backgroundColor = isSpecial ? Constants.specialKeyNormalColour : Constants.keyNormalColour
            }

        default:
            break
        }
    }


    func showRadialMenu(at center: CGPoint, for key: String) {
        if radialMenu == nil {
            if key == "dấu cách" { // spacebar
                radialMenu = RadialMenuView(frame: CGRect(x: 0, y: 0, width: 80, height: 80),
                                            items: [".", ","])
            } else {
                radialMenu = RadialMenuView(frame: CGRect(x: 0, y: 0, width: 120, height: 120),
                                            items: ["◌́", "◌", "◌̀", "◌̣", "◌̃", "◌̉"])
            }
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
            keyboardView.topAnchor.constraint(equalTo: suggestionBar?.bottomAnchor ?? view.topAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
            
        // 🔹 Set background based on system appearance
        keyboardView.backgroundColor = Constants.backgroundColor

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
        
//        let config = MLModelConfiguration()
//        let model = try? v7gpt_2_1_large_20250827(configuration: config)

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
            
            addPadding(to: stackView4, width: buttonWidth/2, key: "")
		case .symbols:
			keyboard = Constants.symbolKeys
            
            addPadding(to: stackView4, width: buttonWidth/2, key: "")
		}
		
		let numRows = keyboard.count
		for row in 0...numRows - 1{
			for col in 0...keyboard[row].count - 1{
				let button = UIButton(type: .custom)
				button.backgroundColor = Constants.keyNormalColour
                button.setTitleColor(Constants.textColor, for: .normal)
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
                
//                button.layer.borderWidth = 1
                
				button.addTarget(self, action: #selector(keyPressedTouchUp), for: .touchUpInside)
				button.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)
				button.addTarget(self, action: #selector(keyUntouched), for: .touchDragExit)
				button.addTarget(self, action: #selector(keyMultiPress(_:event:)), for: .touchDownRepeat)

				if key == "⌫"{
					let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(keyLongPressed(_:)))
					button.addGestureRecognizer(longPressRecognizer)
				}				
				
				button.layer.cornerRadius = buttonWidth/4
                
//                button.layer.shadowOpacity = 0.15
//                button.layer.shadowOffset = CGSize(width: 0, height: 1.5)
//                button.layer.shadowRadius = 1.5

                
				keys.append(button)
				switch row{
                    case 0: stackView1.addArrangedSubview(button)
                    case 1: stackView2.addArrangedSubview(button)
                    case 2: stackView3.addArrangedSubview(button)
                    case 3: stackView4.addArrangedSubview(button)
                    default:
                        break
				}
				
				//top row is longest row so it should decide button width 
				print("button width: ", buttonWidth)
				if key == "⌫" || key == "⏎" || key == "#+=" || key == "ABC" || key == "123" || key == "⇧" {
					button.widthAnchor.constraint(equalToConstant: buttonWidth + buttonWidth/2).isActive = true
					button.layer.setValue(true, forKey: "isSpecial")
					button.backgroundColor = Constants.specialKeyNormalColour
					if key == "⇧" {
						if shiftButtonState != .normal{
							button.backgroundColor = Constants.keyPressedColour
						}
						if shiftButtonState == .caps{
							button.setTitle("⇪", for: .normal)
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
            
                addPadding(to: stackView4, width: buttonWidth/2, key: "")
                break
            case .symbols:
        
                addPadding(to: stackView4, width: buttonWidth/2, key: "")
                break
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
    func handleEmojiButton() {
        for mode in UITextInputMode.activeInputModes {
            if mode.primaryLanguage == "emoji" {
                // Switch to emoji keyboard
//                self.advanceToNextInputMode()
                currentTone = "☻"
                return
            }
        }
        currentTone = "⛫"
        // If no emoji mode found, just cycle input modes
//        self.advanceToNextInputMode()
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
                resetCurrentTone()

            case "dấu cách":
                insertTextAndTriggerChange(" ")
                resetCurrentTone()

            case "⏎":
//                if !pattern.isEmpty { // Maybe not so convenient
//                    emitTopPrediction()
//                } else {
//                    insertTextAndTriggerChange("\n")
//                }
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
                updateSuggestions()
            case "☻": // 🔹 or whatever label you use
                handleEmojiButton()

            default:
                if shiftButtonState == .shift {
                    shiftButtonState = .normal
                    loadKeys()
                }
                insertTextAndTriggerChange(keyToDisplay)
		}
    }
	
	@objc func keyMultiPress(_ sender: UIButton, event: UIEvent){
		guard let originalKey = sender.layer.value(forKey: "original") as? String else {return}

		let touch: UITouch = event.allTouches!.first!
		if (touch.tapCount == 2 && originalKey == "⇧") {
			shiftButtonState = .caps
			loadKeys()
            updateSuggestions()
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
        currentExtraSuggestion = 0
        self.updatePattern()
        self.predict()
    }
}
