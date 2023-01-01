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
        let gunEntity = setupGun()
        
        scene.addEntity(gunEntity)
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view = SKView(frame: view.frame)
        
        setupView()
    }
    private func setupGun() -> GunEntity{
        let bullet = BulletEntity(damage: 1, startImpact: 1300,imageName: "PistolGun")
        let gunEntity = GunEntity(imageName: "PistolGun",shell: bullet,shootingSpeed: 1000)
        if let spriteComponent = gunEntity.component(ofType: SpriteComponent.self){
            spriteComponent.spriteNode.size = CGSize(
                width: spriteComponent.spriteNode.frame.width/view.frame.size.width*70, height: spriteComponent.spriteNode.frame.height/view.frame.size.width*70)
            gunEntity.addComponent(RotationComponent(spriteComponent: spriteComponent, speed: 5))
            spriteComponent.spriteNode.position = CGPoint(x: view.frame.size.width/2, y:20)
        }
        return gunEntity;
    }
    
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
