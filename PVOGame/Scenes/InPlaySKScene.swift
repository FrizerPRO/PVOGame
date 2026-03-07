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
    var graphs = [String: GKGraph]()
    var lastUpdateTime: TimeInterval = 0
    var lastTap = Constants.noTapPoint
    var background = SKSpriteNode()
    var weaponRow: WeaponRow?
    var mainGun: GunEntity?
    let collisionDelegate = CollisionDetectedInGame()

    private var settingsButton: SettingsButton?
    private var settingsMenu: InGameSettingsMenu?
    private var isTouched = false
    private var availableDrones = [AttackDroneEntity]()
    private var activeDrones = [AttackDroneEntity]()
    private(set) var isStarted = false
    var activeDroneCount: Int { activeDrones.count }
    var availableDroneCount: Int { availableDrones.count }

    fileprivate func setupBackground(_ view: SKView) {
        background = SKSpriteNode(color: .black, size: frame.size)
        background.name = Constants.backgroundName
        background.physicsBody = SKPhysicsBody(rectangleOf: frame.size)
        background.physicsBody?.categoryBitMask = Constants.boundsBitMask
        background.physicsBody?.collisionBitMask = 0
        background.physicsBody?.contactTestBitMask = 0
        background.physicsBody?.isDynamic = false
        background.position = CGPoint(x: view.frame.width / 2, y: view.frame.height / 2)
        addChild(background)
    }

    fileprivate func setupGround(_ view: SKView) {
        let groundHeight = frame.height / Constants.GameBalance.groundHeightRatio
        let ground = SKSpriteNode(color: .gray, size: CGSize(width: frame.width, height: groundHeight))
        ground.name = Constants.groundName
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.frame.size)
        ground.physicsBody?.categoryBitMask = Constants.groundBitMask
        ground.physicsBody?.collisionBitMask = 0
        ground.physicsBody?.contactTestBitMask = 0
        ground.physicsBody?.isDynamic = false
        ground.position = CGPoint(x: 0, y: -background.frame.height / 2 + ground.frame.height / 2)
        background.addChild(ground)
    }

    func setupMainMenu(_ view: SKView) {
        setupGunChooseRow(view)
    }

    func setupGunChooseRow(_ view: SKView) {
        weaponRow = WeaponRow(
            frame: CGRect(x: 0, y: Constants.GameBalance.gunPanelTopInset, width: view.frame.width / 2, height: Constants.GameBalance.gunPanelHeight),
            guns: [setupMiniGun(view), setupPistolGun(view), setupDickGun(view)],
            cellSize: Constants.GameBalance.gunCellSize
        )
        guard let weaponRow else { return }
        view.addSubview(weaponRow)

        weaponRow.removeConstraints(weaponRow.constraints)
        weaponRow.pinLeft(to: view, 0)
        weaponRow.pinTop(to: view, Int(Constants.GameBalance.gunPanelTopInset))
        weaponRow.setWidth(view.frame.width).isActive = true
        weaponRow.setHeight(Constants.GameBalance.gunPanelHeight).isActive = true
        weaponRow.mainGun = mainGun
        weaponRow.initUI()
    }

    private func setupSettingsButton(_ view: SKView) {
        let buttonSize = Constants.GameBalance.settingsButtonSize
        let button = SettingsButton(frame: CGRect(origin: .zero, size: buttonSize)) { [weak self] in
            self?.presentPauseMenu()
        }
        view.addSubview(button)
        button.pinLeft(to: view, Int(Constants.GameBalance.settingsButtonInsets.x))
        button.pinTop(to: view, Int(Constants.GameBalance.settingsButtonInsets.y))
        button.setWidth(buttonSize.width).isActive = true
        button.setHeight(buttonSize.height).isActive = true
        button.isHidden = true
        settingsButton = button
    }

    private func setupSettingsMenu(_ view: SKView) {
        let width = view.frame.width * Constants.GameBalance.settingsMenuWidthRatio
        let menu = InGameSettingsMenu(
            frame: CGRect(x: 0, y: 0, width: width, height: Constants.GameBalance.settingsMenuHeight),
            onResume: { [weak self] in
                self?.resumeGame()
            },
            onExit: { [weak self] in
                self?.exitToMainMenu()
            }
        )
        view.addSubview(menu)
        menu.pinCenterX(to: view.centerXAnchor)
        menu.pinCenterY(to: view.centerYAnchor)
        menu.setWidth(width).isActive = true
        menu.setHeight(Constants.GameBalance.settingsMenuHeight).isActive = true
        menu.isHidden = true
        settingsMenu = menu
    }

    private func setupPistolGun(_ view: UIView) -> GunEntity {
        let bullet = BulletEntity(
            damage: Constants.GameBalance.defaultBulletDamage,
            startImpact: Constants.GameBalance.defaultBulletStartImpact,
            imageName: "Bullet"
        )
        return PistolGun(view, shell: bullet)
    }

    private func setupMiniGun(_ view: UIView) -> GunEntity {
        let bullet = BulletEntity(
            damage: Constants.GameBalance.defaultBulletDamage,
            startImpact: Constants.GameBalance.defaultBulletStartImpact,
            imageName: "Bullet"
        )
        return MiniGun(view, shell: bullet)
    }

    private func setupDickGun(_ view: UIView) -> GunEntity {
        let bullet = BulletEntity(
            damage: Constants.GameBalance.defaultBulletDamage,
            startImpact: Constants.GameBalance.defaultBulletStartImpact,
            imageName: "BulletY"
        )
        return DickGun(view, shell: bullet)
    }

    private func setupMainGun(_ view: UIView) {
        mainGun = setupMiniGun(view)
        if let mainGun {
            addEntity(mainGun)
        }
    }

    private func prepareDronePool(_ view: UIView) {
        guard availableDrones.isEmpty, activeDrones.isEmpty else { return }
        for _ in 0..<Constants.GameBalance.dronesPerWave {
            availableDrones.append(setupAttackDrone(view))
        }
    }

    private func setupArmyOfAttackDrones(_ view: UIView) {
        if availableDrones.count < Constants.GameBalance.dronesPerWave {
            prepareDronePool(view)
        }

        for _ in 0..<Constants.GameBalance.dronesPerWave {
            guard let drone = availableDrones.popLast() else { break }
            drone.resetFlight(flyingPath: makeRandomFlyingPath(for: view), speed: Constants.GameBalance.droneSpeed)
            activeDrones.append(drone)
            addEntity(drone)
        }
    }

    private func setupAttackDrone(_ view: UIView) -> AttackDroneEntity {
        AttackDroneEntity(
            damage: 1,
            speed: Constants.GameBalance.droneSpeed,
            imageName: "Drone",
            flyingPath: makeRandomFlyingPath(for: view)
        )
    }

    private func makeRandomFlyingPath(for view: UIView) -> FlyingPath {
        FlyingPath(
            topLevel: view.frame.height,
            bottomLevel: 30,
            leadingLevel: 0,
            trailingLevel: view.frame.width,
            startLevel: view.frame.height,
            endLevel: 0,
            pathGenerator: { flyingPath in
                var nodes = [vector_float2]()
                nodes.append(
                    vector_float2(
                        x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
                        y: Float(flyingPath.startLevel)
                    )
                )
                let counter = Int.random(
                    in: Constants.GameBalance.dronePathMinNodes...Constants.GameBalance.dronePathMaxNodes
                )
                for i in 1..<counter {
                    nodes.append(
                        vector_float2(
                            x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
                            y: flyingPath.topLevel * Float(counter - i) / Float(counter)
                        )
                    )
                }
                nodes.append(vector_float2(x: Float(flyingPath.trailingLevel / 2), y: Float(flyingPath.endLevel)))
                return nodes
            }
        )
    }

    private func presentPauseMenu() {
        guard isStarted else { return }
        settingsMenu?.isHidden = false
        isPaused = true
        isTouched = false
    }

    private func resumeGame() {
        settingsMenu?.isHidden = true
        isPaused = false
        lastUpdateTime = 0
    }

    private func exitToMainMenu() {
        resumeGame()
        stopGame()
    }

    func startGame() {
        guard let view else { return }

        isStarted = true
        isTouched = false
        settingsButton?.isHidden = false
        settingsMenu?.isHidden = true
        weaponRow?.isHidden = true
        setupArmyOfAttackDrones(view)
    }

    func stopGame() {
        isStarted = false
        settingsButton?.isHidden = true
        settingsMenu?.isHidden = true
        weaponRow?.isHidden = false
        isPaused = false
        isTouched = false
        lastUpdateTime = 0
        lastTap = Constants.noTapPoint

        let currentDrones = activeDrones
        activeDrones.removeAll()
        for drone in currentDrones {
            removeEntity(drone)
            availableDrones.append(drone)
        }

        let shells = entities.filter { $0 is Shell }
        for shell in shells {
            removeEntity(shell)
        }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        size = view.frame.size
        backgroundColor = .white
        physicsWorld.contactDelegate = collisionDelegate
        setupBackground(view)
        setupGround(view)
        setupMainGun(view)
        setupMainMenu(view)
        setupSettingsButton(view)
        setupSettingsMenu(view)
        prepareDronePool(view)
    }

    public func addEntity(_ entity: GKEntity) {
        if entities.contains(entity) {
            return
        }
        entities.append(entity)
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode, node.parent == nil {
            addChild(node)
        }
    }

    public func removeEntity(_ entity: GKEntity) {
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode {
            node.removeFromParent()
        }
        if let index = entities.firstIndex(of: entity) {
            entities.remove(at: index)
        }
        if let drone = entity as? AttackDroneEntity,
           let activeIndex = activeDrones.firstIndex(of: drone) {
            activeDrones.remove(at: activeIndex)
            if !availableDrones.contains(drone) {
                availableDrones.append(drone)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        isTouched = true

        if let touch = touches.first {
            let location = touch.location(in: self)
            let touchedNode = atPoint(location)
            if !isStarted && touchedNode.name == Constants.backgroundName {
                startGame()
                return
            }
            lastTap = location
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        isTouched = true
        if let touch = touches.first {
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
        guard let view else { return }
        lastTap = CGPoint(x: view.frame.width / 2, y: view.frame.height)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesEnded(touches, with: event)
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }

        let dt = currentTime - lastUpdateTime
        for entity in entities {
            entity.update(deltaTime: dt)
            if lastTap.equalTo(Constants.noTapPoint) {
                continue
            }
            if let playerControlled = entity.component(ofType: PlayerControlComponent.self) {
                playerControlled.changedFingerPosition(deltaTime: dt, lastTap: lastTap)
                if isTouched {
                    playerControlled.newTap(deltaTime: dt, lastTap: lastTap)
                }
            }
        }
        lastUpdateTime = currentTime
    }
}
