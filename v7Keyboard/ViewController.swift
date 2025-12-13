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
	
	override func viewDidLoad() {
		super.viewDidLoad()
//		instructions.becomeFirstResponder()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		setupUI()
	}
	
	@IBAction func dismissKeyboardPressed(_ sender: Any) {
	instructions.resignFirstResponder()
	}
	
    func setupUI() {
        print("Hello v7")
        
        instructions.text = """
        Bước:
        - Mở cài đặt
        - Cài đặt chung
        - Bàn phím
        - Bàn phím
        - Thêm bàn phím mới
        - Tìm "v7"
        """
        
        instructions.textColor = .black
    }




}

