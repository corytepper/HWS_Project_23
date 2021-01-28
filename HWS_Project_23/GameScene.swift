//
//  GameScene.swift
//  HWS_Project_23
//
//  Created by Cory Tepper on 1/12/21.
//


import AVFoundation
import SpriteKit

enum ForceBomb {
    case never, always, random
}

enum SequenceType: CaseIterable {
    case oneNoBomb, one, twoWithOneBomb, two, three, four, chain, fastChain
}

class GameScene: SKScene {
    // MARK: - Properties
    var gameScore: SKLabelNode!
    
    var score = 0 {
        didSet {
            gameScore.text = "Score: \(score)"
        }
    }
    
    var livesImages = [SKSpriteNode]()
    var lives = 3
    
    var activeSliceBG: SKShapeNode!
    var activeSliceFG: SKShapeNode!
    
    var activeSlicePoints = [CGPoint]()
    
    var isSwooshSoundActive = false
    
    var activeEnemies = [SKSpriteNode]()
    var bombSoundEffect: AVAudioPlayer?
    
    var popUpTime = 0.9
    var sequence = [SequenceType]()
    var sequencePosition = 0
    var chainDelay = 3.0
    var nextSequenceQueued = true
    
    var isGameEnded = false
    
    // Create enemy magic numbers
    let minCreationX = 64
    let maxCreationX = 960
    let creationY = -128
    let minAngularVelocity: CGFloat = -3
    let maxAngularVelocity: CGFloat = 3
    let minFastXVelocity = 8
    let maxFastXVelocity = 15
    let minSlowXVelocity = 3
    let maxSlowXVelocity = 5
    let minYVelocity = 24
    let maxYVeloctiy = 32
    let physicsVelocityMultiplier = 40
    
    // MARK: - Scene Management
    override func didMove(to view: SKView) {
        let background = SKSpriteNode(imageNamed: "sliceBackground")
        background.position = CGPoint(x: 512, y: 384)
        background.blendMode = .replace
        background.zPosition = -1
        addChild(background)
        
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        physicsWorld.speed = 0.85
        
        createScore()
        createLives()
        createSlices()
        
        sequence = [.oneNoBomb, .oneNoBomb, .twoWithOneBomb, .twoWithOneBomb, .three, .one, .chain]
        
        for _ in 0...1000 {
            if let nextSequence = SequenceType.allCases.randomElement() {
                sequence.append(nextSequence)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.tossEnemies()
            
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        // 1. if we active enemies, we loop thru each of them
        if activeEnemies.count > 0 {
            // 2. if any enemy is at or lower than Y position -140, we remove it from the game and our activeEnemies array
            for (index, node) in activeEnemies.enumerated().reversed() {
                if node.position.y < -140 {
                    node.removeAllActions()
                    
                    if node.name == "enemy" || node.name == "bonusEnemy" {
                        node.name = ""
                        subtractLife()
                        
                        node.removeFromParent()
                        activeEnemies.remove(at: index)
                    } else if node.name == "bombContainer" {
                        node.name = ""
                        node.removeFromParent()
                        activeEnemies.remove(at: index)

                    }
                }
            }
        } else {
            // 3. if we dont have any active enemies and we haven't already queued the next enemy sequence, we schedule the next enemy sequence and set nextSequence to be true
            if !nextSequenceQueued {
                DispatchQueue.main.asyncAfter(deadline: .now() + popUpTime) {
                    [weak self] in
                    self?.tossEnemies()
                }
                
                nextSequenceQueued = true
            }
        }
        var bombCount = 0
        
        for node in activeEnemies {
            if node.name == "bombContainer" {
                bombCount += 1
                break
            }
        }
        
        if bombCount == 0 {
            // no bombs - stop the fuse sound!
            bombSoundEffect?.stop()
            bombSoundEffect = nil
        }
    }
    
    // MARK: - Touch Methods
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        // 1. Remove all existing points in the activeSlicePoints array
        activeSlicePoints.removeAll(keepingCapacity: true)
        
        
        // 2. Get the touch location and add it to the activeSlicePoints array.
        let location = touch.location(in: self)
        activeSlicePoints.append(location)
        
        // 3. Call the redrawActiveSlice() method to clear the slice shapes
        redrawActiveSlice()
        
        
        // 4. Remove any actions that are currently attached to the slice shapes. This is important if we are in the middle of a fadeOut(withDuration:) action
        activeSliceBG.removeAllActions()
        activeSliceFG.removeAllActions()
        
        // 5. Set both slice shapes to have an alpha value of 1 so they are fully visible
        activeSliceBG.alpha = 1
        activeSliceFG.alpha = 1
        
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isGameEnded == false else { return }
        
        guard let touch = touches.first else { return }
        let location = touch.location(in:self)
        activeSlicePoints.append(location)
        redrawActiveSlice()
        
        if !isSwooshSoundActive {
            playSwooshSound()
        }
        
        let nodesAtPoint = nodes(at: location)
        
        for case let node as SKSpriteNode in nodesAtPoint {
            if node.name == "enemy" {
                // DESTROY PENGUIN CODE
                // 1. Create a particle effect over the penguin
                if let emitter = SKEmitterNode(fileNamed: "sliceHitEnemy") {
                    emitter.position = node.position
                    addChild(emitter)
                }
                // 2. Clear it's node name so that it cannot be swiped repeatedly
                node.name = ""
                
                // 3. Disable the isDyanmic of it's physics body so that it doesnt carry on falling
                node.physicsBody?.isDynamic = false
                
                // 4. Make the penguin scale out and fade out at the same time
                let scaleOut = SKAction.scale(by: 0.001, duration: 0.2)
                let fadeOut = SKAction.fadeOut(withDuration: 0.2)
                let group = SKAction.group([scaleOut, fadeOut])
                
                // 5. Remove it from the scene
                let sequence = SKAction.sequence([group, .removeFromParent()])
                node.run(sequence)
                
                // 6. Add 1 to the player's score
                score += 1
                
                // 7. Remove the ebemy from the active enemies array
                if let index = activeEnemies.firstIndex(of: node) {
                    activeEnemies.remove(at: index)
                    
                }
                
                // 8. Play a sound when the penguin is hit
                run(SKAction.playSoundFileNamed("whack.caf", waitForCompletion: false))
                
            } else if node.name == "bonusEnemy" {
                if let emitter = SKEmitterNode(fileNamed: "explode") {
                    emitter.position = node.position
                    addChild(emitter)
                }
                
                node.name = ""
                node.physicsBody?.isDynamic = false
                
                let scaleOut = SKAction.scale(to: 0.001, duration: 0.3) // slower than others
                let fadeOut = SKAction.fadeOut(withDuration: 0.3) // slower than others
                let group = SKAction.group([scaleOut, fadeOut])
                let sequence = SKAction.sequence([group, .removeFromParent()])
                node.run(sequence)
                
                score += 5
                
                let scaleUp = SKAction.scale(to: 1.5, duration: 0.5)
                let scaleDown = SKAction.scale(to: 1.0, duration: 0.5)
                let scaleSequence = SKAction.sequence([scaleUp, scaleDown])
                gameScore.run(scaleSequence)
                
                if let index = activeEnemies.firstIndex(of: node) {
                    activeEnemies.remove(at: index)
                }
            
                run(SKAction.playSoundFileNamed("explosion.wav", waitForCompletion: false))
            
            } else if node.name == "bomb" {
                // DESTROY BOMB CODE
                // 1. Reference the node's parent when looking up our position
                guard let bombContainer = node.parent as? SKSpriteNode else { continue }
            
                // 2. Create a different particle effect
                if let emitter = SKEmitterNode(fileNamed: "sliceHitBomb") {
                    emitter.position = bombContainer.position
                    addChild(emitter)
                    
                }
                
                // 3. Change its physics body
                node.name = ""
                bombContainer.physicsBody?.isDynamic = false
                
                
                // 4. Remove the note from the scene
                let scaleOut = SKAction.scale(by: 0.001, duration: 0.2)
                let fadeOut = SKAction.fadeOut(withDuration: 0.2)
                let group = SKAction.group([scaleOut, fadeOut])
                
                let sequence = SKAction.sequence([group, .removeFromParent()])
                bombContainer.run(sequence)
                
                // 5. Remove the node from the active enemies array
                if let index = activeEnemies.firstIndex(of: bombContainer) {
                    activeEnemies.remove(at: index)
                }
                
                // 6. End the game
                run(SKAction.playSoundFileNamed("explosion.caf", waitForCompletion: false))
                endGame(triggeredByBomb: true)
            
            
            }
        }
     
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeSliceBG.run(SKAction.fadeOut(withDuration: 0.25))
        activeSliceFG.run(SKAction.fadeOut(withDuration: 0.25))
    }
    
    // MARK: Helper ethods
    func createScore() {
        gameScore = SKLabelNode(fontNamed: "Chalkduster")
        gameScore.horizontalAlignmentMode = .left
        gameScore.fontSize = 48
        addChild(gameScore)
        
        gameScore.position = CGPoint(x: 8, y: 8)
    }
    
    func createLives() {
        for i in 0 ..< 3 {
            let spriteNode = SKSpriteNode(imageNamed: "sliceLife")
            spriteNode.position = CGPoint(x: CGFloat(834 + (i * 70)), y: 720)
            addChild(spriteNode)
            livesImages.append(spriteNode)
        }
        
    }
    
    func createSlices() {
        activeSliceBG = SKShapeNode()
        activeSliceBG.zPosition = 2
        activeSliceBG.strokeColor = UIColor(red: 1, green: 0.9, blue: 0, alpha: 1)
        activeSliceBG.lineWidth = 9
        addChild(activeSliceBG)
        
        activeSliceFG = SKShapeNode()
        activeSliceFG.zPosition = 3
        activeSliceFG.strokeColor = UIColor.white
        activeSliceFG.lineWidth = 5
        addChild(activeSliceFG)
    }
    
    func redrawActiveSlice() {
        // 1. if we have fewer than two points in our array, we don't have enough data to draw a line so it needs to clear the shapes and exit the method
        if activeSlicePoints.count < 2 {
            activeSliceBG.path = nil
            activeSliceFG.path = nil
            return
        }
        
        //2. if we have more than 12 slice points in our array, we need to remove the oldest ones untl we have at most 12 - this stops the swipe from becoming too long
        if activeSlicePoints.count > 12 {
            activeSlicePoints.removeFirst(activeSlicePoints.count - 12)
        }
        
        // 3. start the line at the position of the first swipe point, then go thru each of the other drawing lines to each point
        let path = UIBezierPath()
        path.move(to: activeSlicePoints[0])
        
        for i in 1 ..< activeSlicePoints.count {
            path.addLine(to: activeSlicePoints[i])
        }
        
        // 4. update the slice shape paths so they get drawn using their design ( line width and color)
        activeSliceBG.path = path.cgPath
        activeSliceFG.path = path.cgPath

    }
    
    func playSwooshSound() {
            isSwooshSoundActive = true
            
            let randomNumber = Int.random(in: 1...3)
            let soundName = "swoosh\(randomNumber).caf"
            
            let swooshSound = SKAction.playSoundFileNamed(soundName, waitForCompletion: true)
            
            run(swooshSound) { [weak self] in
                self?.isSwooshSoundActive = false
            }
    }

    func createEnemy(forceBomb: ForceBomb = .random) {
        let enemy: SKSpriteNode
        
        var enemyType = Int.random(in: 0...7)
        
        if forceBomb == .never {
            enemyType = 1
        } else if forceBomb == .always {
            enemyType = 0
        }
        
        if enemyType == 0 {
            // BOMB CODE
            // 1. create a new SKSpriteNode that will hold the fuse and the bomb image as children, setting it's Z position to 1
            enemy = SKSpriteNode() // container to hold other things
            enemy.zPosition = 1
            enemy.name = "bombContainer"
            
            // 2. Create the bomb image, name it "bomb" and add it to the container
            let bombImage = SKSpriteNode(imageNamed: "sliceBomb")
            bombImage.name = "bomb"
            enemy.addChild(bombImage)
            
            // 3. if the bomb fuse sound effect is playing, stop it
            if bombSoundEffect != nil {
                bombSoundEffect?.stop()
                bombSoundEffect = nil
            }
            
            // 4. Create a new bomb fuse sound effect, then play it
            if let path = Bundle.main.url(forResource: "sliceBombFuse", withExtension: "caf") {
                if let sound = try? AVAudioPlayer(contentsOf: path) {
                    bombSoundEffect = sound
                    sound.play()
                }
            }
          
            
            // 5. Create a particle emitter node, position it at fuse and add to container
            if let emitter = SKEmitterNode(fileNamed: "sliceFuse") {
                emitter.position = CGPoint(x: 76, y: 64)
                enemy.addChild(emitter)
            }
            
            
        } else if enemyType == 2 {
            enemy = SKSpriteNode(imageNamed: "tv")
            run(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "bonusEnemy"
        } else {
            enemy = SKSpriteNode(imageNamed: "penguin")
            run(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "enemy"
        }
        
        
        // POSITION CODE
        // 1. give the enemy a random position off the bottom edge of the screen
        let randomPosition = CGPoint(x: Int.random(in: minCreationX...maxCreationX), y: creationY)
        enemy.position = randomPosition
        
        // 2. Create a random angular veloctiy - spin speed
        let randomAngularVelocity = CGFloat.random(in: minAngularVelocity...maxAngularVelocity)
        let randomXVelocity: Int
        
        
        // 3. Create a random X veloctiy that takes into account the enemy's position
        if randomPosition.x < 256 {
            randomXVelocity = Int.random(in: minFastXVelocity...maxFastXVelocity)
        } else if randomPosition.x < 512 {
            randomXVelocity = Int.random(in: minSlowXVelocity...maxSlowXVelocity)
        } else if randomPosition.x < 768 {
            randomXVelocity = -Int.random(in: minSlowXVelocity...maxSlowXVelocity)
        } else {
            randomXVelocity = -Int.random(in: minFastXVelocity...maxFastXVelocity)
        }
        
        // 4. Create a random Y velocity to have different flying speeds
        let randomYVelocity = Int.random(in: minYVelocity...maxYVeloctiy)
       
        
        
        // 5. Give all enemies a circular physics body and set collisionBitMask to 0 so they do not collide
        enemy.physicsBody = SKPhysicsBody(circleOfRadius: 64)
        enemy.physicsBody?.velocity = CGVector(dx: randomXVelocity * physicsVelocityMultiplier, dy: randomYVelocity * physicsVelocityMultiplier)
        enemy.physicsBody?.angularVelocity = randomAngularVelocity
        enemy.physicsBody?.collisionBitMask = 0 // nothing bounces
        
        addChild(enemy)
        activeEnemies.append(enemy)
    }
    
    func tossEnemies() {
        guard isGameEnded == false else { return }
        
        popUpTime *= 0.991
        chainDelay *= 0.99
        physicsWorld.speed *= 1.02
        
        let sequenceType = sequence[sequencePosition]
        
        switch sequenceType {
        
        case .oneNoBomb:
            createEnemy(forceBomb: .never)
            
        case .one:
            createEnemy()
            
        case .twoWithOneBomb:
            createEnemy(forceBomb: .never)
            createEnemy(forceBomb: .always)
            
        case .two:
            createEnemy()
            createEnemy()
            
        case .three:
            createEnemy()
            createEnemy()
            createEnemy()
        case .four:
            createEnemy()
            createEnemy()
            createEnemy()
            createEnemy()

        case .chain:
            createEnemy()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5.0))
                { [weak self] in self?.createEnemy() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5.0 * 2))
                { [weak self] in self?.createEnemy() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5.0 * 3))
                { [weak self] in self?.createEnemy() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5.0 *  4))
                { [weak self] in self?.createEnemy() }
            
        case .fastChain:
            createEnemy()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10.0))
                { [weak self] in self?.createEnemy() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10.0 * 2))
                { [weak self] in self?.createEnemy() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10.0 * 3))
                { [weak self] in self?.createEnemy() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10.0 *  4))
                { [weak self] in self?.createEnemy() }
        }
        
        sequencePosition += 1
        nextSequenceQueued = false
    }

    
    func endGame(triggeredByBomb: Bool) {
        guard isGameEnded == false else { return }
        
        isGameEnded = true
        physicsWorld.speed = 0
        isUserInteractionEnabled = false
        
        bombSoundEffect?.stop()
        bombSoundEffect = nil
        
        if triggeredByBomb {
            livesImages[0].texture = SKTexture(imageNamed: "sliceLifeGone")
            livesImages[1].texture = SKTexture(imageNamed: "sliceLifeGone")
            livesImages[2].texture = SKTexture(imageNamed: "sliceLifeGone")
        }
        
        let gameOver = SKSpriteNode(imageNamed: "gameOver")
        gameOver.position = CGPoint(x: 512, y: 384)
        gameOver.zPosition = 1
        gameOver.alpha = 0
        gameOver.run(SKAction.fadeIn(withDuration: 1.5))
        
        addChild(gameOver)
    }
    
    func subtractLife() {
        lives -= 1
        
        run(SKAction.playSoundFileNamed("wrong.caf", waitForCompletion: false))
        
        var life: SKSpriteNode
        
        if lives == 2 {
            life = livesImages[0]
        } else if lives == 1 {
            life = livesImages[1]
        } else {
            life = livesImages[2]
            endGame(triggeredByBomb: false)
        }
        
        life.texture = SKTexture(imageNamed: "sliceLifeGone")
        life.xScale = 1.3
        life.yScale = 1.3
        life.run(SKAction.scale(to: 1, duration: 0.1))
    }
        
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
 
    


}
