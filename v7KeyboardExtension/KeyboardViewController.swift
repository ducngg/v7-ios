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
    
    let gptTokenizer = GPTTokenizer()
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
    
    private func adjustCase(for word: String) -> String {
        if shiftButtonState == .caps {
            return word.uppercased()
        } else if shiftButtonState == .shift || (!pattern.isEmpty && pattern.first!.isUppercase) {
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return word
    }
    
    func updateSuggestions() {
        // Clear previous buttons
        suggestionBar?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let tokenizer = self.gptTokenizer else { return }

        var filtered = tokenizer.filter(
            pattern: pattern,
            predictions: currentPrediction,
            toneMark: currentTone,
            extraSuggestion: currentExtraSuggestion
        )
        
        filtered = filtered.filter { ![",", "."].contains($0) }

        // 🚀 Logic for XPACE (The Spacebar)
        // Only show prediction if the user has actually started typing (pattern is not empty)
        if let firstWord = filtered.first, !pattern.isEmpty && uiCodeState == Constants.OMEGA_UI_CODE {
            let adjustedFirst = adjustCase(for: firstWord)
            xpace?.setTitle(adjustedFirst, for: .normal)
            
            // Show the text-only highlight pill
            let highlightPill = xpace?.superview?.viewWithTag(99)
            highlightPill?.isHidden = false
            
            xenter?.setTitle(Constants.XENTER, for: .normal)
        } else {
            // Default back to "Space" if no pattern is active
            xpace?.setTitle(Constants.SPACE, for: .normal)
            xpace?.superview?.viewWithTag(99)?.isHidden = true
        }

        // 🟦 Show ALL suggestions in the bar (including the first one)
        for (index, word) in filtered.enumerated() {
            let adjusted = adjustCase(for: word)

            let button = UIButton(type: .system)
            button.setTitle(adjusted, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .regular)
            button.setTitleColor(Constants.textColor, for: .normal)
            button.layer.cornerRadius = 6
            button.addTarget(self, action: #selector(didTapSuggestion(_:)), for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

            // Highlight the first item in the suggestion bar if pattern exists
            if index == 0 && !pattern.isEmpty {
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
        
        // 🔸 Delete current pattern AND // 🔸 Insert selected word + space
        // 🔹 Find first index from right that is a special
        if let lastSpecialIndex = pattern.lastIndex(where: { gptTokenizer!.specials.contains($0) }) {
            let deleteCount = pattern.distance(from: lastSpecialIndex, to: pattern.endIndex) - 1
            for _ in 0..<deleteCount {
                proxy.deleteBackward()
            }
            
            insertTextAndTriggerChange(word)
        } else {
            for _ in 0..<pattern.count {
                proxy.deleteBackward()
            }
            
            insertTextAndTriggerChange(word + " ")
        }
        
        // 🔸 Insert selected word + space
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
        cooker?.updateBias(with: word)
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
        if pattern == "" {
            xenter?.setTitle(Constants.ENTER, for: .normal)
        }
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
                if !pattern.isEmpty { emitTopPrediction() }
                insertTextAndTriggerChange(term)
                
                // 🔹 Reset key color when menu dismissed
                resetButtonBackgroundColor(btn: keyButton)
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

        let isSpecial = ["⌫", "#+=", "ABC", "123", "⇧", "⏎", "☻"].contains(key)

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
            case "☻": customMultiplier = 1.1
            case "⌫": customMultiplier = 1.5
            case "⏎": customMultiplier = 2.6
            case "123": customMultiplier = 1.3
            case "ABC": customMultiplier = 1.3
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
                if key == Constants.SPACE {
                    self.xpace = btn
                    
                    // Create a "Pill" view that sits behind the text
                    let highlightPill = UIView()
                    highlightPill.backgroundColor = Constants.keyPressedColour
                    highlightPill.layer.cornerRadius = 4
                    highlightPill.isUserInteractionEnabled = false
                    highlightPill.translatesAutoresizingMaskIntoConstraints = false
                    highlightPill.tag = 99
                    highlightPill.isHidden = true // Hidden by default
                    
                    container.addSubview(highlightPill)
                    
                    NSLayoutConstraint.activate([
                        highlightPill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                        highlightPill.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                        // Make the pill slightly larger than expected text bounds
                        highlightPill.heightAnchor.constraint(equalToConstant: 28),
                        highlightPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 70)
                    ])
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
    func handleXpace() {
        guard let xpaceButton = self.xpace else {
            // Fallback if xpace isn't initialized
            insertTextAndTriggerChange(" ")
            return
        }

        let currentTitle = xpaceButton.title(for: .normal)

        // If the title is NOT the default space constant, it's a prediction
        if currentTitle != Constants.SPACE && currentTitle != "" {
            emitTopPrediction()
        } else {
            // Standard spacebar behavior
            insertTextAndTriggerChange(" ")
            resetCurrentTone()
        }
    }
    func handleXenter() {
        guard let xenterButton = self.xenter else {
            insertTextAndTriggerChange("\n")
            return
        }

        let currentTitle = xenterButton.title(for: .normal)

        // If the button is in "XENTER" mode, clean up and commit
        if currentTitle == Constants.XENTER {
            // 1. Reset xpace to standard space
            xpace?.setTitle(Constants.SPACE, for: .normal)
            xpace?.superview?.viewWithTag(99)?.isHidden = true
            
            // 2. Reset xenter back to the return icon/text
            xenterButton.setTitle(Constants.ENTER, for: .normal)
            
        } else {
            // Standard Enter behavior
            insertTextAndTriggerChange("\n")
        }
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
                handleXpace()

            case Constants.ENTER:
                handleXenter()

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
    
    func delChunk() {
        let context = proxy.documentContextBeforeInput ?? ""
        guard !context.isEmpty else { return }
        guard let tokenizer = gptTokenizer else { return }

        let specials = tokenizer.specials

        var deleteCount = 0
        var index = context.index(before: context.endIndex)

        let lastChar = context[index]

        // 🔥 CASE 1: Last char is special → delete all consecutive SAME specials
        if specials.contains(lastChar) {
            deleteCount = 1

            var currentIndex = index

            while currentIndex > context.startIndex {
                let prevIndex = context.index(before: currentIndex)
                let prevChar = context[prevIndex]

                // stop if different char OR not special
                if prevChar != lastChar || !specials.contains(prevChar) {
                    break
                }

                deleteCount += 1
                currentIndex = prevIndex
            }
        } else {
            // 🔥 CASE 2: Delete full token until hitting a special
            while true {
                let char = context[index]
                if specials.contains(char) { break }

                deleteCount += 1

                if index == context.startIndex { break }
                index = context.index(before: index)
            }
        }

        // Apply deletion
        for _ in 0..<deleteCount {
            proxy.deleteBackward()
        }

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

	
	override func textDidChange(_ textInput: UITextInput?) {
		// The app has just changed the document's contents, the document context has been updated.
        currentExtraSuggestion = 0
        self.updatePattern()
        self.llm_predict()
    }
}
