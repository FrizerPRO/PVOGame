//
//  InGameSettingsMenu.swift
//  PVOGame
//
//  Created by Frizer on 09.01.2023.
//

import UIKit

class InGameSettingsMenu: UIStackView {
    let label: UILabel
    let exitButton: UIButton
    override init(frame: CGRect){
        exitButton = UIButton(frame: CGRect(x: 0, y: 0, width: frame.width - 10 , height: frame.height/2 - 10))
        label = UILabel(frame: CGRect(x: 0, y: 0, width: frame.width - 10 , height: frame.height/2 - 10))
        super.init(frame: frame)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
