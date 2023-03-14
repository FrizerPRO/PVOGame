//
//  GameViewController.swift
//  PVOGame
//
//  Created by Frizer on 01.12.2022.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {
    fileprivate func setupView() {
        // Load 'GameScene.sks' as a GKScene. This provides gameplay related content
        // including entities and graphs.
        let scene = InPlaySKScene(size: view.frame.size)
        
//        let gunEntity = setupGun()
//        for _ in 1...10{
//            let droneEntity = setupAttackDrone(scene: scene)
//            scene.addEntity(droneEntity)
//        }
//        scene.addEntity(gunEntity)
        
        // Get the SKScene from the loaded GKScene
        // Copy gameplay related content over to the scene
        
        // Set the scale mode to scale to fit the window
        scene.scaleMode = .aspectFill
        // Present the scene
        if let view = self.view as! SKView? {
            view.presentScene(scene)
            view.ignoresSiblingOrder = true
            
            view.showsFPS = true
            view.showsNodeCount = true
        }
    }
//    private func setupAttackDrone(scene: SKScene)->AttackDroneEntity{
//        let flyingPath = FlyingPath(topLevel: view.frame.height, bottomLevel: 30, leadingLevel: 0, trailingLevel: view.frame.width, startLevel: view.frame.height, endLevel: 0, pathGenerator: {flyingPath in
//            var nodes = [vector_float2]()
//            nodes.append(vector_float2(x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
//                                       y: Float(flyingPath.startLevel)))
//            let counter = Int.random(in: 15...200)
//            for i in 1 ..< counter{
//                nodes.append(vector_float2(x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
//                                           y: flyingPath.topLevel * Float(counter - i)/Float(counter)))
//            }
//            nodes.append(vector_float2(x: Float(flyingPath.trailingLevel/2), y: Float(flyingPath.endLevel)))
//            return nodes
//        })
//        return AttackDroneEntity(damage: 1, speed: 500, imageName: "Dildo",flyingPath: flyingPath)
//    }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view = SKView(frame: view.frame)
        
        setupView()
    }
//    private func setupGun() -> GunEntity{
//        let bullet = BulletEntity(damage: 1, startImpact: 1450,imageName: "Bullet")
//        let gunEntity = GunEntity(imageName: "PistolGun",shell: bullet,shootingSpeed: 5000,rotateSpeed: 5,label: "Pistol")
//        if let spriteComponent = gunEntity.component(ofType: SpriteComponent.self){
//            spriteComponent.spriteNode.size = CGSize(
//                width: spriteComponent.spriteNode.frame.width/view.frame.size.width*70, height: spriteComponent.spriteNode.frame.height/view.frame.size.width*70)
//            gunEntity.addComponent(RotationComponent(spriteComponent: spriteComponent, speed: gunEntity.rotateSpeed))
//            spriteComponent.spriteNode.position = CGPoint(x: view.frame.size.width/2, y:20)
//        }
//        return gunEntity;
//    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
