//
//  WeaponRow.swift
//  PVOGame
//
//  Created by Frizer on 13.03.2023.
//

import UIKit

class WeaponRow: UIScrollView {
    var stackView: UIStackView?
    var guns: [GunEntity]
    var cellSize: CGSize
    weak var mainGun: GunEntity?
    init(frame:CGRect, guns:[GunEntity],cellSize: CGSize){
        self.guns = guns
        self.cellSize = cellSize
        super.init(frame: frame)
    }
    
    func initUI(){
        translatesAutoresizingMaskIntoConstraints = false
        initStackView()
        addGunsInStack()
    }
    func initStackView(){
        stackView = UIStackView()
        stackView?.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView!)
        stackView?.pinLeft(to: self,10)
        stackView?.pinRight(to: self,10)
        stackView?.pinTop(to: self)
        stackView?.pinBottom(to: self)
        stackView?.heightAnchor.constraint(equalTo: self.heightAnchor).isActive = true
        stackView?.axis = .horizontal
        stackView?.alignment = .center
        stackView?.distribution = .equalSpacing
        stackView?.spacing = 10
        
        self.backgroundColor = .black
        self.layer.borderWidth = 5
        self.layer.borderColor = UIColor.green.cgColor
        self.layer.cornerRadius = 20
    }
    
    func addGunsInStack(){
        for gun in guns{
            var weaponCell = WeaponCell(frame: CGRect(x: 0, y: 0, width: cellSize.width, height: cellSize.height),
                                        imageName: gun.imageName, gunEntity: gun)
            weaponCell.mainGun = mainGun
            stackView?.addArrangedSubview(weaponCell)
        }
        contentSize = stackView!.frame.size
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
