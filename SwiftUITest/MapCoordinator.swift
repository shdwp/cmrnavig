//
//  MapCoordinator.swift
//  SwiftUITest
//
//  Created by Vasyl Horbachenko on 6/19/19.
//  Copyright © 2019 Medtronic. All rights reserved.
//

import Foundation
import Combine
import OverpassSwift

class MapCoordinator: MapViewCoordinator {
    let client = OverpassClient(URL(string: "https://lz4.overpass-api.de/api/interpreter")!)
    let subject = PassthroughSubject<OverpassResult, Error>()
    
    var lastResult: OverpassResult?
    var lastBounds: OverpassBounds?
    
    init() {
        
    }
}

// MARK: Publisher
extension MapCoordinator {
    func receive<S>(subscriber: S) where S : Subscriber, Error == S.Failure, OverpassResult == S.Input {
        self.subject.receive(subscriber: subscriber)
    }
}

// MARK: Subscriber
extension MapCoordinator {
    func receive(subscription: Subscription) {
        subscription.request(.unlimited)
    }
    
    func receive(_ input: OverpassBounds) -> Subscribers.Demand {
        Swift.print("receive value \(input)")
        
        if input == .arbitrary {
            self.lastResult = nil
            self.lastBounds = nil
            return .unlimited
        }
        
        var detalization = ""
        switch input.diameter {
        case 0...0.01:
             detalization = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|service"
        case 0.01...0.03:
             detalization = "motorway|trunk|primary|secondary|tertiary|unclassified|residential"
        case 0.03...0.07:
             detalization = "motorway|trunk|primary|secondary|tertiary"
        case 0.07...0.1:
            detalization = "motorway|trunk|primary"
        default:
            detalization = "motorway|trunk"
        }

        var bounds = [input, ]
        if let previousBounds = self.lastResult?.bounds {
            bounds = input.difference(previousBounds)
        }

        let _ = self.client
            .request(OverpassRequest {
                ForEach(bounds) { (index, bound) -> [OverpassStatement] in
                    Union(into: String(index)) {
                        Query(.relation) {
                            Bounding(bound)
                            Tag("highway", matches: detalization)
                        }

                        Recurse(.down)
                    }

                    Print(from: String(index))
                }
            })
            .sink {
                if var lastResult = self.lastResult {
                    lastResult = lastResult.expanded(with: $0, newBounds: input)
                    
                    self.lastBounds = lastResult.bounds
                    self.lastResult = lastResult
                } else {
                    self.lastResult = $0
                    self.lastBounds = $0.bounds
                }

                if let result = self.lastResult {
                    self.subject.send(result)
                }
        }

        return .unlimited
    }
    
    func receive(completion: Subscribers.Completion<Error>) {
        
    }
}
