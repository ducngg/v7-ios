//
//  Radial.swift
//  v7Keyboard
//
//  Created by Duc on 07/09/2025.
//
import UIKit

class RadialMenuView: UIView {
    var selectedIndex: Int? = nil
    var selectedItem: String? = nil

    var items: [String]
    var numberOfSectors: Int { items.count }
    let angleOffset: CGFloat = -.pi / 2

    init(frame: CGRect, items: [String]) {
        self.items = items
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2

        let font = UIFont.systemFont(ofSize: 16, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Constants.textColor,
            .font: font
        ]

        for i in 0..<numberOfSectors {
            let startAngle = CGFloat(i) * .pi * 2 / CGFloat(numberOfSectors) + angleOffset
            let endAngle = CGFloat(i + 1) * .pi * 2 / CGFloat(numberOfSectors) + angleOffset

            ctx.setFillColor((i == selectedIndex) ? Constants.radialMenuSelected : Constants.radialMenuUnselected)
            ctx.move(to: center)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.fillPath()

            // label
            let angle = startAngle + (endAngle - startAngle) / 2
            let labelCenter = CGPoint(
                x: center.x + cos(angle) * (radius - 20),
                y: center.y + sin(angle) * (radius - 20)
            )

            let text = items[i]
            let textSize = (text as NSString).size(withAttributes: textAttributes)
            let textRect = CGRect(
                x: labelCenter.x - textSize.width / 2,
                y: labelCenter.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: textAttributes)
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
        selectedItem = items[index]

        setNeedsDisplay()
    }
}

