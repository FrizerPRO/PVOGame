//
//  WeaponCell.swift
//  PVOGame
//
//  Created by Frizer on 12.03.2023.
//

import UIKit

class WeaponCell: UIButton {
    let imageName: String
    let gunEntity: GunEntity
    var image: UIImageView?
    var shootRateLabel: UILabel?
    var damageRateLabel: UILabel?
    var rotateSpeedLabel: UILabel?
    var nameLabel: UILabel?
    weak var mainGun: GunEntity?
    
    init(frame: CGRect, imageName: String, gunEntity: GunEntity){
        self.imageName = imageName
        self.gunEntity = gunEntity
        super.init(frame: frame)
        initView()
    }
    func initView(){
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setWidth(self.frame.width)
        self.setHeight(self.frame.height)
        initImage()
        initShootRateLabel()
        initDamageRateLabel()
        initRotateSpeedLabel()
        initBackground()
        initNameLabel()
        addTarget(self, action: #selector(buttonIsPushed), for: .touchUpInside)
    }
    
    @objc
    func buttonIsPushed(){
        mainGun?.copyFrom(gun: gunEntity)
    }
    func initBackground(){
        self.backgroundColor = .black
        self.layer.borderWidth = 5
        self.layer.borderColor = UIColor.green.cgColor
        self.layer.cornerRadius = 20
    }
    func initImage(){
        image = UIImageView(image: UIImage(named: imageName))
        image?.image = image?.image?.scalePreservingAspectRatio(targetSize: CGSize(width: frame.width/3,height: frame.height))
        self.addSubview(image!)
        image?.pinRight(to: self.centerXAnchor,10)
        image?.pinCenterY(to: self.centerYAnchor)
    }
    func initNameLabel(){
        nameLabel = UILabel()
        nameLabel?.text = gunEntity.label
        nameLabel?.textColor = .green
        nameLabel?.font = .boldSystemFont(ofSize: 30)
        self.addSubview(nameLabel!)
        nameLabel?.pinLeft(to: self.centerXAnchor,10)
        nameLabel?.pinTop(to: self.topAnchor, 30)
    }

    func initShootRateLabel(){
        shootRateLabel = UILabel()
        shootRateLabel?.text = "Shoot rate : \(gunEntity.shootingSpeed)"
        shootRateLabel?.textColor = .green
        shootRateLabel?.font = .systemFont(ofSize: 15)
        self.addSubview(shootRateLabel!)
        shootRateLabel?.pinLeft(to: self.centerXAnchor,10)
        shootRateLabel?.pinBottom(to: self.bottomAnchor,20)
    }
    func initDamageRateLabel(){
        damageRateLabel = UILabel()
        damageRateLabel?.text = "Damage rate : \(gunEntity.shell.damage)"
        damageRateLabel?.textColor = .green
        damageRateLabel?.font = .systemFont(ofSize: 15)
        self.addSubview(damageRateLabel!)
        damageRateLabel?.pinLeft(to: self.centerXAnchor,10)
        damageRateLabel?.pinBottom(to: shootRateLabel!.topAnchor,10)
    }
    func initRotateSpeedLabel(){
        rotateSpeedLabel = UILabel()
        rotateSpeedLabel?.text = "Rotate speed : \(gunEntity.shell.damage)"
        rotateSpeedLabel?.textColor = .green
        rotateSpeedLabel?.font = .systemFont(ofSize: 15)

        self.addSubview(rotateSpeedLabel!)
        rotateSpeedLabel?.pinLeft(to: self.centerXAnchor,10)
        rotateSpeedLabel?.pinBottom(to: damageRateLabel!.topAnchor,10)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
