//
//  SettingsButton.swift
//  PVOGame
//
//  Created by Frizer on 09.01.2023.
//

import UIKit

class SettingsButton: UIButton {
    let callInGameSettingsMenu: ()->Void
    let image: UIImageView
    init(frame:CGRect, callSettingsMenu: @escaping ()->Void){
        image = UIImageView(image: UIImage(imageLiteralResourceName: "Settings"))
        self.callInGameSettingsMenu = callSettingsMenu
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .green
        
    }
    private func setupImage(){
        self.addSubview(image)
        image.pinCenter(to: self)
        image.translatesAutoresizingMaskIntoConstraints = false
        image.frame.size = self.frame.size
        self.addTarget(self, action: #selector(didTouchButton), for: .touchUpInside)
    }
    
    @objc
    private func didTouchButton(){
        self.isHidden = true
        callInGameSettingsMenu()
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
