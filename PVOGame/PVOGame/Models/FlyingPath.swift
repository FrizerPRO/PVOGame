//
//  FlyingZone.swift
//  PVOGame
//
//  Created by Frizer on 04.01.2023.
//

import UIKit
import GameplayKit
public class FlyingPath{
    public let topLevel: Float
    public let bottomLevel: Float
    public let leadingLevel: Float
    public let trailingLevel: Float
    public let startLevel: Float
    public let endLevel: Float
    public var nodes = [vector_float2]()
    public let pathGenerator: (FlyingPath)->[vector_float2]
    init(topLevel: CGFloat,bottomLevel: CGFloat,leadingLevel: CGFloat,trailingLevel: CGFloat,startLevel: CGFloat,endLevel: CGFloat, pathGenerator: @escaping (FlyingPath)->[vector_float2]){
        self.topLevel = Float(topLevel)
        self.bottomLevel = Float(bottomLevel)
        self.leadingLevel = Float(leadingLevel)
        self.trailingLevel = Float(trailingLevel)
        self.startLevel = Float(startLevel)
        self.endLevel = Float(endLevel)
        self.pathGenerator = pathGenerator
        generatePathes()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func getLength()->CGFloat{
        guard let nodes = nodes as? [GKGraphNode2D]
        else{
            return 0
        }
        var sum: Float = 0
        for i in 1..<nodes.count{
            sum += nodes[i-1].cost(to: nodes[i]);
        }
        return CGFloat(sum)
    }
    private func generatePathes(){
        if !nodes.isEmpty{
            nodes.removeAll()
        }
        nodes = pathGenerator(self)
    }
}
