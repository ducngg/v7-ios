//
//  KeyboardViewController.swift
//
//  Created by Ethan Sarif-Kattan on 09/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//  Extended by Duc
//

import UIKit
import CoreML

final class KeyContainerView: UIView {

    weak var button: UIButton?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let button = button else { return super.hitTest(point, with: event) }

        // Expand hit area
        let expandedFrame = button.frame.insetBy(dx: -3, dy: -6)

        if expandedFrame.contains(point) {
            return button
        }

        return super.hitTest(point, with: event)
    }
}

var proxy : UITextDocumentProxy!

class KeyboardViewController: UIInputViewController, UIScrollViewDelegate {
    let keyPressHaptic = UIImpactFeedbackGenerator(style: .light)

    var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }
    var keyboardHeightConstraint: NSLayoutConstraint?
    var suggestionBarHeightConstraint: NSLayoutConstraint?

    var suggestionBar: UIStackView?
	var keyboardView: UIView!
	var keys: [UIButton] = []
    var xpace: UIButton?
    var xenter: UIButton?
	var backspaceTimer: Timer?
    
    var cooker: Cooker?
    
    var lastRawContextWithoutPattern: String?
    var lastInputArray: MLMultiArray?
    var toneInfoLabel: UILabel?
    var currentTone: String = "" {
        didSet {
            toneInfoLabel?.text = currentTone.isEmpty ? Constants.defaultToneLabelDisplay(uiCode: uiCodeState) : currentTone
            toneInfoLabel?.font = Constants.textFont(uiCode: uiCodeState, size: 16)
        }
    }
    func resetCurrentTone() {
        currentTone = ""
    }

    var currentPrediction: PredictionResult = (candidates: [], scores: [])
    
    var currentExtraSuggestion: Int = 0
    var pattern: String = ""
    var limboBuffer: String = ""

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
	
    var uiCodeState: Int = 0
	var keyboardState: KeyboardState = .letters
	var shiftButtonState: ShiftButtonState = .normal
    var hasEnteredRadialMenu = false
    private var panStartPoint: CGPoint?   // Store where the gesture began
	
    var suggestionScrollView: UIScrollView?
	@IBOutlet weak var stackView1: UIStackView!
	@IBOutlet weak var stackView2: UIStackView!
	@IBOutlet weak var stackView3: UIStackView!
	@IBOutlet weak var stackView4: UIStackView!
    
    func updateViewHeightConstraint() {
        
        let keyboardHeight: CGFloat = Constants.keyboardHeight(isLandscape: isLandscape)
        let suggestionHeight: CGFloat = Constants.suggestionBarHeight(isLandscape: isLandscape)
        
        // Update keyboard constraint
        if let existing = keyboardHeightConstraint {
            view.removeConstraint(existing)
        }
        let kHeightConstraint = NSLayoutConstraint(
            item: view!,
            attribute: .height,
            relatedBy: .equal,
            toItem: nil,
            attribute: .notAnAttribute,
            multiplier: 1.0,
            constant: keyboardHeight + suggestionHeight
        )
        view.addConstraint(kHeightConstraint)
        keyboardHeightConstraint = kHeightConstraint
        
        // Update suggestion bar height
        suggestionBarHeightConstraint?.constant = suggestionHeight
    }
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        keyboardView.frame.size = view.frame.size
    }
	
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateViewHeightConstraint()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { _ in
            self.updateViewHeightConstraint()
            self.loadKeys()
            self.loadSuggestionBar() // refresh suggestion bar layout
        })
    }

    override func viewDidLoad() {
//        NSLog("%0.4f", CGFloat.pi)

        super.viewDidLoad()
        keyPressHaptic.prepare()

        proxy = textDocumentProxy as UITextDocumentProxy
        
        uiCodeState = CacheManager.loadUICodeState()

        cooker = Cooker()
        
        loadInterface()
        updatePattern()
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
    
    @objc func didTapToneInfoLabel() {
        uiCodeState += 1

        if uiCodeState >= Constants.NUMBER_OF_UI_CODES {
            uiCodeState = 0
        }
        
        // Persist state
        CacheManager.saveUICodeState(uiCodeState)
        
        toneInfoLabel?.text = currentTone.isEmpty
            ? Constants.defaultToneLabelDisplay(uiCode: uiCodeState)
            : currentTone
        
        toneInfoLabel!.font = Constants.textFont(uiCode: uiCodeState, size: 16)
        
        loadKeys()
    }

    func loadSuggestionBar() {
        if suggestionBar != nil {
            return
        }
        
        let container = UIStackView()
        container.axis = .horizontal
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
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
        let infoLabelWrapper = UIView()

        let infoLabel = UILabel()
        infoLabel.text = Constants.defaultToneLabelDisplay(uiCode: uiCodeState)
        infoLabel.font = Constants.textFont(uiCode: uiCodeState, size: 16)
        infoLabel.textAlignment = .center
        infoLabel.textColor = Constants.textColor
        infoLabel.backgroundColor = Constants.backgroundColor
        infoLabel.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapToneInfoLabel))
        infoLabel.addGestureRecognizer(tap)

        infoLabelWrapper.addSubview(infoLabel)
        infoLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: infoLabelWrapper.leadingAnchor, constant: 8), // 👈 left padding
            infoLabel.trailingAnchor.constraint(equalTo: infoLabelWrapper.trailingAnchor),
            infoLabel.topAnchor.constraint(equalTo: infoLabelWrapper.topAnchor),
            infoLabel.bottomAnchor.constraint(equalTo: infoLabelWrapper.bottomAnchor),
            infoLabelWrapper.widthAnchor.constraint(equalToConstant: 48) // 30 + padding
        ])

        container.addArrangedSubview(infoLabelWrapper)
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
        ])
        
        // Suggestion bar height constraint
        let barHeight: CGFloat = Constants.suggestionBarHeight(isLandscape: isLandscape)
        let heightConstraint = container.heightAnchor.constraint(equalToConstant: barHeight)
        heightConstraint.isActive = true
        suggestionBarHeightConstraint = heightConstraint
        
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalTo: container.heightAnchor),
            
            bar.topAnchor.constraint(equalTo: scrollView.topAnchor),
            bar.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            bar.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    func loadInterface() {
        // Load suggestion bar first
        loadSuggestionBar()
        
        // Load keyboard view
        let keyboardNib = UINib(nibName: "Keyboard", bundle: nil)
        keyboardView = keyboardNib.instantiate(withOwner: self, options: nil)[0] as? UIView
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        
        // TODO: Might need to add very top constraints
        NSLayoutConstraint.activate([
            keyboardView.topAnchor.constraint(equalTo: suggestionBar?.bottomAnchor ?? view.topAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        keyboardView.backgroundColor = Constants.backgroundColor
        
        // Load keys
        loadKeys()
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
    
    private func adjustCase(for phrase: String, segments: [String]) -> String {
        // 1. Absolute Caps Lock handles everything globally
        if shiftButtonState == .caps {
            return phrase.uppercased()
        }
        
        let words = phrase.components(separatedBy: .whitespaces)
        
        // 2. Pair-matching check: Ensure counts match perfectly
        if words.count == segments.count && !segments.isEmpty {
            var adjustedWords: [String] = []
            
            for i in 0..<words.count {
                let word = words[i]
                let segment = segments[i]
                
                // Only care if the first character of the input segment is uppercase
                if let firstChar = segment.first, firstChar.isUppercase {
                    let capitalizedWord = word.prefix(1).uppercased() + word.dropFirst()
                    adjustedWords.append(capitalizedWord)
                } else {
                    adjustedWords.append(word)
                }
            }
            return adjustedWords.joined(separator: " ")
        }
        
        // 3. Fallback Logic: Standard shifting fallback if segment mapping breaks
        if shiftButtonState == .shift || (!limboBuffer.isEmpty && limboBuffer.first!.isUppercase) {
            return phrase.prefix(1).uppercased() + phrase.dropFirst()
        }
        
        return phrase
    }
    
    func updateSuggestions() {
        // Clear previous buttons
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let cooker = self.cooker else {
            keyboardLogger.debug("❌ cooker is nil")
            return
        }
        
        // 2. Determine which input signal to use
        // If we are in ALPHA_UI_CODE, use limboBuffer
        // Otherwise, fallback to the committed pattern
        let activeSignals = (uiCodeState == Constants.ALPHA_UI_CODE) ? limboBuffer : pattern

        // 3. Fetch suggestions from your logic engine
        var filtered = cooker.cookSuggestions(
            signals: activeSignals,
            predictions: currentPrediction,
            toneMark: currentTone,
            extraSuggestion: currentExtraSuggestion
        )
        
        if filtered.isEmpty {
            filtered = [limboBuffer]
            reloadLiveLimbo(tear: false)
        }
        
        // 4. Extract segments from the actual user buffer
        let segments = cooker.tokenizer!.signalTearer(signals: limboBuffer)

        // 5. Adjust case for all filtered suggestions mapping against the segments
        filtered = filtered.map { phrase in
            return adjustCase(for: phrase, segments: segments)
        }

        // 🟦 Show ALL suggestions in the bar (including the first one)
        for (index, word) in filtered.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(word, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .regular)
            button.setTitleColor(Constants.textColor, for: .normal)
            button.layer.cornerRadius = 6
            button.addTarget(self, action: #selector(didTapSuggestion(_:)), for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            
            // Highlight the first item in the suggestion bar if pattern exists
            if index == 0 && (!pattern.isEmpty || !limboBuffer.isEmpty) {
                button.backgroundColor = Constants.keyPressedColour
            } else {
                button.backgroundColor = .clear
            }

            suggestionBar?.addArrangedSubview(button)
        }
    }
    
    // Keep the @objc exposed version for button taps
    @objc func didTapSuggestion(_ sender: UIButton) {
        didTapSuggestion(sender, fromRadialMenu: false)
    }
    func didTapSuggestion(_ sender: UIButton, fromRadialMenu: Bool = false) {
        guard let word = sender.title(for: .normal) else { return }
        
        if uiCodeState == Constants.ALPHA_UI_CODE {
            // Set to empty fist so it won't be emitted
            resetLimbo()
            
            if let lastSpecialIndex = pattern.lastIndex(where: { cooker?.tokenizer?.specials.contains($0) ?? false }) {
                insertTextAndTriggerChange(word)
            } else {
                insertTextAndTriggerChange(word + " ")
            }
        } else {
            // 🔸 Legacy Logic for committed patterns (Normal State)
            if let lastSpecialIndex = pattern.lastIndex(where: { cooker?.tokenizer?.specials.contains($0) ?? false }) {
                let deleteCount = pattern.distance(from: lastSpecialIndex, to: pattern.endIndex) - 1
                for _ in 0..<deleteCount {
                    textDocumentProxy.deleteBackward()
                }
                insertTextAndTriggerChange(word)
            } else {
                for _ in 0..<pattern.count {
                    textDocumentProxy.deleteBackward()
                }
                insertTextAndTriggerChange(word + " ")
            }
        }
        
        // 🔸 UI Cleanup
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // 🔸 Reset state
        if !fromRadialMenu {
            resetCurrentTone()
        }
        
        if shiftButtonState != .caps {
            shiftButtonState = .normal
            loadKeys()
        }
        
        // 🔸 Logic updates
        cooker?.updateBias(with: word)
        
        // Final check to clear any remaining underlines
        self.limboDidChange()
        self.textDidChange(nil)
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
    
    private func resetLimbo() {
        limboBuffer = ""

        textDocumentProxy.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0)
        )

        textDocumentProxy.unmarkText()
    }
    
    func reloadLiveLimbo(tear: Bool = true) {
        guard let cooker = self.cooker, let tokenizer = cooker.tokenizer else {
            return
        }
        
        if limboBuffer.isEmpty {
            // ❌ Instead of unmarkText(), use an empty marked string
            // This explicitly tells iOS to "zero out" the underlined area
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            
            // Optional: Follow up with unmark to fully close the session
            textDocumentProxy.unmarkText()
            return
        }

        let displayString: String
        if tear {
            let segments = tokenizer.signalTearer(signals: limboBuffer)
            displayString = segments.joined(separator: " ")
        } else {
            displayString = limboBuffer
        }
        
        textDocumentProxy.setMarkedText(displayString, selectedRange: NSRange(location: displayString.count, length: 0))
    }

    func llm_predict() {
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

        guard let cooker = self.cooker else {
            keyboardLogger.debug("❌ cooker is nil")
            return
        }
        guard let tokenizer = cooker.tokenizer else {
            keyboardLogger.debug("❌ tokenizer is nil")
            return
        }
        
        var inputArray = tokenizer.tokenize(text: rawContextWithoutPattern)
        if inputArray.count == 0 || rawContextWithoutPattern.trimmingCharacters(in: .whitespaces).isEmpty {
            inputArray = tokenizer.tokenize(text: Constants.DEFAULT_CONTEXT)
        }

        if tokenizer.isSameInput(inputArray, lastInputArray) {
            self.updateSuggestions()
            return
        }
        lastInputArray = inputArray
        
        keyboardLogger.debug("preding")
        DispatchQueue.global(qos: .userInitiated).async {
            let start = DispatchTime.now()

            if let predictions = cooker.llm_predict(
                input: inputArray,
                biasVector: cooker.biasVectorManager?.biasVector ?? [],
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
//                if !pattern.isEmpty { emitTopPrediction() }
//                insertTextAndTriggerChange(term)
                
                // 🔹 Reset key color when menu dismissed
                resetButtonBackgroundColor(btn: keyButton)
                return
            }

            if let selectedItem = radialMenu.selectedItem {
                if selectedItem == "." || selectedItem == "," {
                    // Special punctuation handling
                    if !limboBuffer.isEmpty {
//                        emitTopPrediction()
                        
                        insertTextAndTriggerChange(limboBuffer)
                        resetLimbo()
                        self.limboDidChange()
                    }
                    if (proxy.documentContextBeforeInput ?? "").hasSuffix(" ") {
                        proxy.deleteBackward()
                    }
                    insertTextAndTriggerChange(selectedItem + " ")
                    resetCurrentTone()
                } else {
                    // Normal tone-mark behavior
                    currentTone = selectedItem
                    
                    // insertLimboAndTriggerChange(term)
                    insertLimboAndTriggerChange("")
                }
            } else {
                // No radial selection
//                if !limboBuffer.isEmpty { emitTopPrediction() }
//                insertTextAndTriggerChange(term)
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
            resetButtonBackgroundColor(btn: keyButton)

        default:
            break
        }
    }


    func showRadialMenu(at center: CGPoint, for key: String) {
        if radialMenu == nil {
            if key == Constants.SPACE {
                radialMenu = RadialMenuView(frame: CGRect(x: 0, y: 0, width: 80, height: 80),
                                            items: [".", ","])
            } else if key == Constants.XPACE {
                radialMenu = RadialMenuView(frame: CGRect(x: 0, y: 0, width: 120, height: 120),
                                            items: ["◌́", "◌", "◌̀", "◌̣", "◌̃", "◌̉"])
            }
            else {
                return
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
    
    private func resetButtonBackgroundColor(
        btn: UIButton
    ) {
        guard let originalKey = btn.layer.value(forKey: "original") as? String else {return}
        guard let isSpecial = btn.layer.value(forKey: "isSpecial") as? Bool else {return}
        btn.backgroundColor = isSpecial ? Constants.specialKeyNormalColour : Constants.keyNormalColour
        if originalKey == Constants.SPACE {
            btn.backgroundColor = Constants.spaceKeyNormalColour
        }
    }
	
    private func applyWidthRules(
        container: UIView,
        btn: UIButton,
        key: String,
        rowIndex: Int,
        totalMultiplier: CGFloat
    ) {

        let isSpecial = ["⌫", "#+=", Constants.ABC, "123", "⇧", "⏎", Constants.EMOJI].contains(key)

        if isSpecial {
            btn.layer.setValue(true, forKey: "isSpecial")
            btn.backgroundColor = key == "⇧" && shiftButtonState != .normal
                ? Constants.keyPressedColour
                : Constants.specialKeyNormalColour

            if key == "⇧", shiftButtonState == .caps {
                btn.setTitle("⇪", for: .normal)
            }

            let customMultiplier: CGFloat
            switch key {
            case Constants.EMOJI: customMultiplier = 1.1
            case Constants.XPACE: customMultiplier = 1.4
            case "⌫": customMultiplier = 1.5
            case "⏎": customMultiplier = 2.2
            case "123": customMultiplier = 1.3
            case Constants.ABC: customMultiplier = 1.3
            case "#+=": customMultiplier = 1.3
            default: customMultiplier = 1.4
            }

            container.widthAnchor.constraint(
                equalTo: stackView1.widthAnchor,
                multiplier: totalMultiplier * customMultiplier
            ).isActive = true

            return
        }

        // Special wider row for numbers/symbols
        if (keyboardState == .numbers || keyboardState == .symbols), rowIndex == 2 {
            container.widthAnchor.constraint(
                equalTo: stackView1.widthAnchor,
                multiplier: totalMultiplier * 1.4
            ).isActive = true
            return
        }

        // Normal key
        if key != Constants.SPACE {
            container.widthAnchor.constraint(
                equalTo: stackView1.widthAnchor,
                multiplier: totalMultiplier * 0.95
            ).isActive = true
        }
    }

    func loadKeys() {

        // CLEAN OLD VIEWS
        keys.forEach { $0.removeFromSuperview() }
        keys.removeAll()
        xpace = nil // Reset reference
        xenter = nil
        
        let type = textDocumentProxy.keyboardType
        switch type {
        case .numberPad, .decimalPad, .phonePad:
            self.keyboardState = .numbers
        case .emailAddress, .twitter, .webSearch:
            self.keyboardState = .letters
        default:
            break
        }
        
        // SELECT KEYBOARD LAYOUT
        let keyboard: [[String]]
        switch keyboardState {
        case .letters: keyboard = Constants.letterKeys
        case .numbers: keyboard = Constants.numberKeys
        case .symbols: keyboard = Constants.symbolKeys
        }

        // ORIENTATION-SAFE: SIZE BASED ON STACKVIEW WIDTH
        let maxKeyCount = (keyboard.map { $0.count }.max() ?? 10) + 1
        let buttonWidthMultiplier = 1.0 / CGFloat(maxKeyCount)

        // ADD ROWS + BUTTONS
        let rows = [stackView1, stackView2, stackView3, stackView4]
        // 🔥 FULL CLEAN RESET (IMPORTANT)
        rows.forEach { row in
            row?.arrangedSubviews.forEach {
                row?.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }
        // Row-level spacing
        rows.forEach { row in
            row?.isLayoutMarginsRelativeArrangement = true
            row?.layoutMargins = Constants.rowMargins(isLandscape: isLandscape)
            row?.spacing = Constants.rowSpacing(isLandscape: isLandscape)
        }
        for (rowIndex, rowKeys) in keyboard.enumerated() {
            let rowStack = rows[rowIndex]
            rowStack?.clipsToBounds = false
            rowStack?.layer.masksToBounds = false

            for key in rowKeys {

                // 🟩 CONTAINER (NEW)
                let container = KeyContainerView()
                container.clipsToBounds = false
                
                // 🔳 SHADOW VIEW (NEW)
                let shadowView = UIView()
                shadowView.backgroundColor = Constants.buttonShadowColor
                shadowView.layer.cornerRadius = 6
                shadowView.translatesAutoresizingMaskIntoConstraints = false

                // 🔘 BUTTON (YOUR ORIGINAL)
                let btn = UIButton(type: .custom)
                container.button = btn
                btn.setTitleColor(Constants.textColor, for: .normal)
                btn.accessibilityLabel = key // Add this line

                if !Constants.specialKeys.contains(key) {
                    btn.titleLabel?.font = Constants.textFont(uiCode: uiCodeState)
                }
                if key == Constants.SPACE {
                    btn.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .regular)
                }

                btn.layer.cornerRadius = 6
                btn.clipsToBounds = true
                btn.translatesAutoresizingMaskIntoConstraints = false

                // ADD SUBVIEWS (ORDER MATTERS)
                container.addSubview(shadowView)
                
                // 🔥 XPACE HIGHLIGHT LOGIC
                if key == Constants.XPACE {
                    self.xpace = btn
                }
                if key == Constants.ENTER {
                    self.xenter = btn
                }
    
                container.addSubview(btn)

                // 🧷 CONSTRAINTS (NEW)
                NSLayoutConstraint.activate([
                    // Button fills container
                    btn.topAnchor.constraint(equalTo: container.topAnchor),
                    btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),

                    // Shadow slightly below button
                    shadowView.topAnchor.constraint(equalTo: btn.topAnchor, constant: 1),
                    shadowView.leadingAnchor.constraint(equalTo: btn.leadingAnchor),
                    shadowView.trailingAnchor.constraint(equalTo: btn.trailingAnchor),
                    shadowView.bottomAnchor.constraint(equalTo: btn.bottomAnchor, constant: 1),
                ])

                // SHIFT DISPLAY (UNCHANGED)
                let display: String
                if key == Constants.SPACE {
                    display = key
                } else {
                    display = shiftButtonState == .normal ? key : key.capitalized
                }
                btn.setTitle(display, for: .normal)
                btn.titleEdgeInsets = UIEdgeInsets(
                    top: -1,
                    left: 0,
                    bottom: 1,
                    right: 0
                )

                // LAYER VALUES (UNCHANGED)
                btn.layer.setValue(key, forKey: "original")
                btn.layer.setValue(display, forKey: "keyToDisplay")
                btn.layer.setValue(false, forKey: "isSpecial")
                
                resetButtonBackgroundColor(btn: btn)

                // GESTURES (UNCHANGED)
                if Constants.allowedRadialKeys.contains(key.lowercased()) {
                    btn.addGestureRecognizer(UIPanGestureRecognizer(
                        target: self, action: #selector(handleKeyPan(_:))
                    ))
                }

                if key == "⌫" {
                    btn.addGestureRecognizer(UILongPressGestureRecognizer(
                        target: self, action: #selector(keyLongPressed(_:))
                    ))
                }
                
                if key == Constants.EMOJI {
                    btn.addTarget(
                        self,
                        action: #selector(handleInputModeList(from:with:)),
                        for: .allTouchEvents
                    )
                }

                // BUTTON TARGETS (UNCHANGED)
                btn.addTarget(self, action: #selector(keyPressedTouchUp), for: .touchUpInside)
                btn.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)
                btn.addTarget(self, action: #selector(keyUntouched), for: .touchDragExit)
                btn.addTarget(self, action: #selector(keyMultiPress(_:event:)), for: .touchDownRepeat)

                // ✅ IMPORTANT: add container, not button
                rowStack?.addArrangedSubview(container)
//                container.layoutMargins = UIEdgeInsets(top: -4, left: -4, bottom: -4, right: -4)

                // Keep your keys array intact
                keys.append(btn)

                // WIDTH RULES (APPLY TO CONTAINER NOW)
                applyWidthRules(
                    container: container,
                    btn: btn,
                    key: key,
                    rowIndex: rowIndex,
                    totalMultiplier: buttonWidthMultiplier
                )
            }
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
        if uiCodeState == Constants.ALPHA_UI_CODE && !limboBuffer.isEmpty {
            deleteLimboAndTriggerChange()
        } else {
            // Otherwise, perform a standard backspace on the document
            deleteBackwardAndTriggerChange()
        }
    }
    
    func handleEmojiButton() {
        for mode in UITextInputMode.activeInputModes {
            if mode.primaryLanguage == "emoji" {
                // Switch to emoji keyboard
//                self.advanceToNextInputMode()
                currentTone = Constants.EMOJI
                return
            }
        }
        currentTone = "⛫"
        // If no emoji mode found, just cycle input modes
//        self.advanceToNextInputMode()
    }
    func handleSpace() {
        // 1. Handle Limbo/ALPHA state first
        if uiCodeState == Constants.ALPHA_UI_CODE && !limboBuffer.isEmpty {
            insertTextAndTriggerChange(limboBuffer)
            resetLimbo()
            insertTextAndTriggerChange(" ")
            self.limboDidChange()
            return // Exit early so we don't insert a second space
        }
        
        insertTextAndTriggerChange(" ")
    }
    func handleXpace() {
        // 1. Handle Limbo/ALPHA state first
        if uiCodeState == Constants.ALPHA_UI_CODE && !limboBuffer.isEmpty {
            if !limboBuffer.hasSuffix(" ") {
                limboBuffer += " "
                limboDidChange()
            }
            return
        }
        
        insertTextAndTriggerChange(" ")
    }
    func handleXenter() {
        // 1. Handle Limbo/ALPHA state first
        if uiCodeState == Constants.ALPHA_UI_CODE && !limboBuffer.isEmpty {
            insertTextAndTriggerChange(limboBuffer)
            resetLimbo()
            insertTextAndTriggerChange("\n")
            self.limboDidChange()
            return // Exit early so we don't insert a second space
        }
        
        insertTextAndTriggerChange("\n")
    }
    
    // For gradients
//    override func viewDidLayoutSubviews() {
//        super.viewDidLayoutSubviews()
//
//        for btn in keys {
//            for layer in btn.layer.sublayers ?? [] {
//                if let gradient = layer as? CAGradientLayer {
//                    gradient.frame = btn.bounds
//                }
//            }
//        }
//    }
    
    func insertLimboAndTriggerChange(_ key: String) {
        // 1. Update the internal raw string (e.g., "nham")
        limboBuffer += key
        limboDidChange()
    }
    func deleteLimboAndTriggerChange() {
        guard !limboBuffer.isEmpty else {
            limboDidChange()
            return
        }
        
        // 1. Remove the last character from the buffer
        limboBuffer.removeLast()
        limboDidChange()
    }
	@IBAction func keyPressedTouchUp(_ sender: UIButton) {
        keyPressHaptic.impactOccurred()
		guard let originalKey = sender.layer.value(forKey: "original") as? String, let keyToDisplay = sender.layer.value(forKey: "keyToDisplay") as? String else {return}
        resetButtonBackgroundColor(btn: sender)

		switch originalKey {
            case "⌫":
                if shiftButtonState == .shift {
                    shiftButtonState = .normal
                    loadKeys()
                }
                handleDeleteButtonPressed()
                resetCurrentTone()

            case Constants.SPACE:
                handleSpace()
            
            case Constants.XPACE:
                handleXpace()

            case Constants.ENTER:
                handleXenter()

            case "123":
                changeKeyboardToNumberKeys()
            case Constants.ABC:
                changeKeyboardToLetterKeys()
            case "#+=":
                changeKeyboardToSymbolKeys()
            case "⇧":
                shiftButtonState = shiftButtonState == .normal ? .shift : .normal
                loadKeys()
                updateSuggestions()
            case Constants.EMOJI:
                handleEmojiButton()

            default:
                if shiftButtonState == .shift {
                    shiftButtonState = .normal
                    loadKeys()
                }
            
            if Constants.CHARS.contains(originalKey) && uiCodeState == Constants.ALPHA_UI_CODE {
                insertLimboAndTriggerChange(keyToDisplay)
            } else {
                // If it's a number, punctuation, or uiCodeState is active, commit immediately
                insertTextAndTriggerChange(limboBuffer)
                resetLimbo()
                self.limboDidChange()
                insertTextAndTriggerChange(keyToDisplay)
            }
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
    func delChunk() {
        // 1. Check if we are in the ALPHA/Limbo state
        if uiCodeState == Constants.ALPHA_UI_CODE && !limboBuffer.isEmpty {
            guard let tokenizer = cooker?.tokenizer else { return }
            
            var segments = tokenizer.signalTearer(signals: limboBuffer)
            
            if !segments.isEmpty {
                // 3. Remove the last syllable chunk
                segments.removeLast()
                
                // 4. Reconstruct the raw buffer (e.g., "nha")
                limboBuffer = segments.joined()
                self.limboDidChange()
            }
            return // Exit because we handled the limbo deletion
        }

        // --- CASE 2: Standard Document Deletion (Existing Logic) ---
        let context = proxy.documentContextBeforeInput ?? ""
        guard !context.isEmpty, let tokenizer = cooker?.tokenizer else { return }

        let specials = tokenizer.specials
        var deleteCount = 0
        var index = context.index(before: context.endIndex)
        let lastChar = context[index]

        if specials.contains(lastChar) {
            deleteCount = 1
            var currentIndex = index
            while currentIndex > context.startIndex {
                let prevIndex = context.index(before: currentIndex)
                if context[prevIndex] != lastChar || !specials.contains(context[prevIndex]) { break }
                deleteCount += 1
                currentIndex = prevIndex
            }
        } else {
            while true {
                if specials.contains(context[index]) { break }
                deleteCount += 1
                if index == context.startIndex { break }
                index = context.index(before: index)
            }
        }

        for _ in 0..<deleteCount { proxy.deleteBackward() }
        self.textDidChange(nil)
    }
	
	@objc func keyLongPressed(_ gesture: UIGestureRecognizer){
		if gesture.state == .began {
			backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { (timer) in
//				self.handleDeleteButtonPressed()
                self.delChunk()
			}
		} else if gesture.state == .ended || gesture.state == .cancelled {
			backspaceTimer?.invalidate()
			backspaceTimer = nil
            resetButtonBackgroundColor(btn: gesture.view as! UIButton)
		}
	}
	
	@objc func keyUntouched(_ sender: UIButton){
        resetButtonBackgroundColor(btn: sender)
	}
	
	@objc func keyTouchDown(_ sender: UIButton){
		sender.backgroundColor = Constants.keyPressedColour
	}
	
	override func textWillChange(_ textInput: UITextInput?) {
		// The app is about to change the document's contents. Perform any preparation here.
	}
    
    func insertTextAndTriggerChange(_ text: String) {
        if text == Constants.SPACE {
            return
        }
        proxy.insertText(text)
        self.textDidChange(nil)
    }

    func deleteBackwardAndTriggerChange() {
        proxy.deleteBackward()
        self.textDidChange(nil)
    }
    
    func limboDidChange() {
        self.reloadLiveLimbo()
        self.llm_predict()
    }
	
    override func textDidChange(_ textInput: UITextInput?) {
        // 1. Check if the document is actually empty
        // We check the proxy to see if there is any context before the cursor
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        if context.isEmpty {
            limboBuffer = ""
        }
        
        // Standard update flow if context exists
        currentExtraSuggestion = 0
        self.updatePattern()
        self.reloadLiveLimbo()
        self.llm_predict()
    }
    
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
//        proxy.insertText("1")

        if !limboBuffer.isEmpty {
            insertTextAndTriggerChange(limboBuffer)
            resetLimbo()
            self.limboDidChange()
//            proxy.insertText("2")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
//        proxy.insertText("3")

        super.viewWillDisappear(animated)
        if !limboBuffer.isEmpty {
            insertTextAndTriggerChange(limboBuffer)
            resetLimbo()
            self.limboDidChange()
//            proxy.insertText("4")

        }
    }
}
