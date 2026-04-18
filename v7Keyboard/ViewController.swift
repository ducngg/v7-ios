//
//  ViewController.swift
//
//  Created by Ethan Sarif-Kattan on 09/07/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
	@IBOutlet weak var instructions: UITextView!
	@IBOutlet weak var dismissKeyboardButton: UIButton!

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private struct KeyboardDemo {
        let title: String
        let subtitle: String
        let keyboardType: UIKeyboardType
        let placeholder: String
    }

    private let keyboardDemos: [KeyboardDemo] = [
        KeyboardDemo(title: "default", subtitle: "General purpose keyboard", keyboardType: .default, placeholder: "Type anything"),
        KeyboardDemo(title: "asciiCapable", subtitle: "ASCII-only characters", keyboardType: .asciiCapable, placeholder: "ASCII input"),
        KeyboardDemo(title: "numbersAndPunctuation", subtitle: "Digits and punctuation", keyboardType: .numbersAndPunctuation, placeholder: "123, symbols..."),
        KeyboardDemo(title: "URL", subtitle: "Optimized for website entry", keyboardType: .URL, placeholder: "https://example.com"),
        KeyboardDemo(title: "numberPad", subtitle: "Numeric keypad", keyboardType: .numberPad, placeholder: "012345"),
        KeyboardDemo(title: "phonePad", subtitle: "Phone dialing layout", keyboardType: .phonePad, placeholder: "+84 912 345 678"),
        KeyboardDemo(title: "namePhonePad", subtitle: "Names and phone symbols", keyboardType: .namePhonePad, placeholder: "Nguyen Van A"),
        KeyboardDemo(title: "emailAddress", subtitle: "Email-focused keyboard", keyboardType: .emailAddress, placeholder: "name@example.com"),
        KeyboardDemo(title: "decimalPad", subtitle: "Numeric keypad with decimal separator", keyboardType: .decimalPad, placeholder: "123.45"),
        KeyboardDemo(title: "twitter", subtitle: "Quick access to @ and #", keyboardType: .twitter, placeholder: "@username #topic"),
        KeyboardDemo(title: "webSearch", subtitle: "Keyboard for search queries", keyboardType: .webSearch, placeholder: "Search terms"),
        KeyboardDemo(title: "asciiCapableNumberPad", subtitle: "ASCII-capable numeric keypad", keyboardType: .asciiCapableNumberPad, placeholder: "ASCII digits")
    ]
	
	override func viewDidLoad() {
		super.viewDidLoad()
        setupUI()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
	}
	
	@IBAction func dismissKeyboardPressed(_ sender: Any) {
        view.endEditing(true)
	}
	
    func setupUI() {
        title = "v7 Keyboard Lab"

        instructions.isHidden = true
        dismissKeyboardButton.isHidden = true

        configureScrollView()
        configureContent()
        configureDismissGesture()
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureContent() {
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])

        contentStack.addArrangedSubview(makeHeaderView())
        contentStack.addArrangedSubview(makeVietnameseInstructionView())

        for demo in keyboardDemos {
            contentStack.addArrangedSubview(makeKeyboardRow(for: demo))
        }

        contentStack.addArrangedSubview(makeAlphabetInfoView())
        contentStack.addArrangedSubview(v7version())
    }

    private func makeHeaderView() -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        let subtitleLabel = UILabel()

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "UIKeyboardType Samples"
        titleLabel.font = .systemFont(ofSize: 27, weight: .bold)
        titleLabel.textColor = .label

        subtitleLabel.text = "Tap each field to preview keyboard behavior"
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeVietnameseInstructionView() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        container.layer.cornerRadius = 14
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.9).cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Hướng dẫn cài đặt bàn phím v7"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.numberOfLines = 0
        bodyLabel.font = .systemFont(ofSize: 18, weight: .regular)
        bodyLabel.textColor = .label
        bodyLabel.text = """
1. Mở Cài đặt (Settings) 
2. Chọn Cài đặt chung
3. Chọn Bàn phím (Keyboard)
4. Chọn Bàn phím (lần nữa)
5. Chọn Thêm bàn phím mới
6. Tìm và chọn \"v7\"
"""

        container.addSubview(titleLabel)
        container.addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func makeKeyboardRow(for demo: KeyboardDemo) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        container.layer.cornerRadius = 14
        container.layer.borderColor = UIColor.separator.cgColor
        container.layer.borderWidth = 1

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = demo.title
        nameLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = .label

        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = demo.subtitle
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabel

        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.keyboardType = demo.keyboardType
        textField.placeholder = demo.placeholder
        textField.borderStyle = .roundedRect
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.autocapitalizationType = .none

        container.addSubview(nameLabel)
        container.addSubview(detailLabel)
        container.addSubview(textField)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),

            textField.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 9),
            textField.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            textField.heightAnchor.constraint(equalToConstant: 40)
        ])

        return container
    }

    private func makeAlphabetInfoView() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "alphabet resolves to: \(UIKeyboardType.alphabet.rawValue) (device-dependent)."
        return label
    }

    private func v7version() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "v7 version: 1.6.0"
        return label
    }

    private func configureDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapOutside))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTapOutside() {
        view.endEditing(true)
    }

}

