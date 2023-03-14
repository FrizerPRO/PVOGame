//
//  InPlayScene.swift
//  PVOGame
//
//  Created by Frizer on 04.12.2022.
//

import UIKit
import SpriteKit
import GameplayKit

class InPlaySKScene: SKScene {
    var entities = [GKEntity]()
    var graphs = [String : GKGraph]()
    var lastUpdateTime: TimeInterval = 0
    var lastTap = CGPoint(x: 0.5,y: -1)
    var penultimateTap = CGPoint(x: 0.5, y: -1)
    var background = SKSpriteNode()
    let menuButton = MenuButton(size: CGSize(width: 40, height: 30))
    var exitMenu : ExitMenu?
    var isTouched = false
    var agent = GKAgent2D()
    var weaponRow : WeaponRow?
    var mainGun : GunEntity?
    let collisionDelegate = CollisionDetectedInGame()
    var isStarted = false
    
    fileprivate func setupBackground(_ view: SKView) {
        background = SKSpriteNode(color: .black, size: frame.size)
        background.name = Constants.backgroundName
        background.physicsBody = SKPhysicsBody(rectangleOf: frame.size)
        background.physicsBody?.categoryBitMask = Constants.boundsBitMask
        background.physicsBody?.collisionBitMask = 0
        background.physicsBody?.contactTestBitMask = 0
        background.physicsBody?.isDynamic = false
        background.position = CGPoint(x: view.frame.width/2, y: view.frame.height/2)
        addChild(background)
    }
    
    fileprivate func setupGround(_ view: SKView) {
        let ground = SKSpriteNode(color: .gray, size: CGSize(width: frame.width, height: frame.height/30))
        ground.name = Constants.groundName
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.frame.size)
        ground.physicsBody?.categoryBitMask = Constants.groundBitMask
        ground.physicsBody?.collisionBitMask = 0
        ground.physicsBody?.contactTestBitMask = 0
        ground.physicsBody?.isDynamic = false
        ground.position = CGPoint(x: 0, y: -background.frame.height/2 + ground.frame.height/2)
        background.addChild(ground)
        
    }
    fileprivate func setupMenuButton(_ view: SKView){
        menuButton.position = CGPoint(x:  40, y:  view.frame.height - 60)
        menuButton.zPosition = 1
        addChild(menuButton)
    }
    fileprivate func setupExitMenu(_ view: SKView){
        exitMenu = ExitMenu(size: CGSize(width: 8*view.frame.width/10, height: 2*view.frame.width/10))
        exitMenu?.zPosition = 1
        exitMenu?.position = CGPoint(x:  view.frame.width/2, y:  view.frame.height/2)
        addChild(exitMenu!)
        exitMenu?.isHidden = true
    }
    func setupMainMenu(_ view: SKView){
        setupGunChooseRow(view)
    }
    func setupGunChooseRow(_ view: SKView){
        weaponRow = WeaponRow(frame: CGRect(x: 0, y: 100, width: view.frame.width/2, height: 200), guns: [setupMiniGun(view),setupPistolGun(view)],
                            cellSize: CGSize(width: 300, height: 170))
        view.addSubview(weaponRow!)
        
        weaponRow?.removeConstraints(weaponRow!.constraints)
        weaponRow?.pinLeft(to: view,0)
        weaponRow?.pinTop(to: view,100)
        weaponRow?.setWidth(view.frame.width).isActive = true
        weaponRow?.setHeight(195).isActive = true
        weaponRow?.mainGun = mainGun
        weaponRow?.initUI()
    }
    private func setupPistolGun(_ view: UIView) -> GunEntity{
        let bullet = BulletEntity(damage: 1, startImpact: 1450,imageName: "Bullet")
        let gunEntity = PistolGun(view, shell: bullet)
        return gunEntity;
    }
    private func setupMiniGun(_ view: UIView) -> GunEntity{
        let bullet = BulletEntity(damage: 1, startImpact: 1450,imageName: "Bullet")
        let gunEntity = MiniGun(view, shell: bullet)
        return gunEntity;
    }

    private func setupMainGun(_ view: UIView){
        mainGun = setupMiniGun(view)
        addEntity(mainGun!)
    }
    private func setupArmyOfAttackDrones(_ view: UIView){
        for _ in 1...1000{
            addEntity(setupAttackDrone(view))
        }
    }
    private func setupAttackDrone(_ view: UIView)->AttackDroneEntity{
        let flyingPath = FlyingPath(topLevel: view.frame.height, bottomLevel: 30, leadingLevel: 0, trailingLevel: view.frame.width, startLevel: view.frame.height, endLevel: 0, pathGenerator: {flyingPath in
            var nodes = [vector_float2]()
            nodes.append(vector_float2(x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
                                       y: Float(flyingPath.startLevel)))
            let counter = Int.random(in: 15...200)
            for i in 1 ..< counter{
                nodes.append(vector_float2(x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
                                           y: flyingPath.topLevel * Float(counter - i)/Float(counter)))
            }
            nodes.append(vector_float2(x: Float(flyingPath.trailingLevel/2), y: Float(flyingPath.endLevel)))
            return nodes
        })
        return AttackDroneEntity(damage: 1, speed: 500, imageName: "Drone",flyingPath: flyingPath)
    }
    func startGame(){
        guard let view = view
        else{
            return
        }
        isStarted = true
        isTouched = false
        menuButton.isHidden = false
        weaponRow?.isHidden = true
        setupArmyOfAttackDrones(view)
    }
    func stopGame(){
        isStarted = false
        menuButton.isHidden = true
        weaponRow?.isHidden = false
        for entity in entities {
            if let drone = entity as? AttackDroneEntity{
                if let index = entities.firstIndex(of: drone){
                    entities.remove(at: index)
                }
                if let sprite = drone.component(ofType: SpriteComponent.self){
                    scene?.removeChildren(in: [sprite.spriteNode])
                }
            }
        }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        self.size = view.frame.size
        backgroundColor = .white
        physicsWorld.contactDelegate = collisionDelegate
        setupBackground(view)
        setupGround(view)
        setupMenuButton(view)
        setupExitMenu(view)
        setupMainGun(view)
        setupMainMenu(view)
        
        menuButton.isHidden = true
    }
    
    public func addEntity(_ entity: GKEntity) {
        entities.append(entity)
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode{
            addChild(node)
        }
    }
    public func removeEntity(_ entity: GKEntity) {
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode{
            node.removeFromParent()
        }
        if let index = entities.firstIndex(of: entity){
            entities.remove(at: index)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        isTouched = true
        
        if let touch = touches.first{
            let location = touch.location(in: self)
            let touchedNode = atPoint(location)
            if(!isStarted && touchedNode.name == Constants.backgroundName){
                startGame()
                return
            } else if touchedNode.name == Constants.menuButtonName{
                exitMenu?.isHidden = false
                isPaused = true
                return
            } else if touchedNode.name == Constants.cancelExitFromGameButtonName{
                exitMenu?.isHidden = true
                isPaused = false
                isTouched = false
                lastUpdateTime = 0
                return
            } else if touchedNode.name == Constants.exitFromGameButtonName{
                exitMenu?.isHidden = true
                isPaused = false
                isTouched = false
                lastUpdateTime = 0
                stopGame()
                return
            }
            penultimateTap = lastTap
            lastTap = touch.location(in: self)
        }
        
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        isTouched = true
        if let touch = touches.first{
            penultimateTap = lastTap
            lastTap = touch.location(in: self)
        }
    }
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        super.touchesEstimatedPropertiesUpdated(touches)
        touchesBegan(touches, with: nil)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        isTouched = false
        guard let view = view
        else{
            return
        }
        lastTap = CGPoint(x: view.frame.width/2,y: view.frame.height)
        penultimateTap = lastTap
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesEnded(touches, with: event)
    }
    
    
    override func update(_ currentTime: TimeInterval) {

        super.update(currentTime)
        // Called before each frame is rendered
        // Initialize _lastUpdateTime if it has not already been
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
            return
        }
        // Calculate time since last update
        let dt = currentTime - self.lastUpdateTime
            for entity in self.entities {
                entity.update(deltaTime: dt)
                if lastTap.equalTo(CGPoint(x: 0.5,y: -1)){
                    continue
                }
                if let playerControlled = entity.component(ofType: PlayerControlComponent.self){
                    playerControlled.changedFingerPosition(deltaTime: dt, lastTap: lastTap)
                    if isTouched {
                        playerControlled.newTap(deltaTime: dt, lastTap: lastTap)
                    }
                }

        }
        self.lastUpdateTime = currentTime
    }
    
}
