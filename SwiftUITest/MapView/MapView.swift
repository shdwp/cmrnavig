//
//  MapView.swift
//  SwiftUITest
//
//  Created by Vasyl Horbachenko on 6/12/19.
//  Copyright © 2019 Medtronic. All rights reserved.
//

import SwiftUI
import OverpassSwift
import Combine

protocol MapViewCoordinator: Publisher, Subscriber where Failure == Error, Output == OverpassResult, Input == OverpassBounds { }

fileprivate class BindableCoordinator<T: MapViewCoordinator>: BindableObject, Subject {
    typealias Output = T.Input
    typealias Failure = T.Failure
    
    typealias Refresh = Bool
    typealias PublisherType = PassthroughSubject<Refresh, Never>
    
    private let passtrough = PassthroughSubject<T.Input, T.Failure>()

    let didChange: PublisherType = .init()
    var sink: Subscribers.Sink<T>?
    var latestResult: T.Output?

    init(_ coordinator: T) {
        // connect coordinator to latestResult & didChange
        let _ = coordinator
            .print()
            .sink { (result) in
                self.latestResult = result
                self.didChange.send(true)
        }
        
        // connect coordinator to self publisher
        self.subscribe(coordinator)
    }
    
    // MARK: Subject
    func send(_ value: OverpassBounds) {
        self.passtrough.send(value)
    }
    
    func send(completion: Subscribers.Completion<T.Failure>) {
        self.passtrough.send(completion: completion)
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, S.Failure == T.Failure, S.Input == Output {
        self.passtrough.receive(subscriber: subscriber)
    }
    
}

struct MapView<T: MapViewCoordinator> : View {
    fileprivate struct Scroll {
        var location: OverpassPoint
        var anchor: OverpassPoint? = nil
    }
    
    fileprivate struct Scale {
        var factor: CGFloat
        var anchor: CGFloat? = nil
    }

    @ObjectBinding fileprivate var coordinator: BindableCoordinator<T>
    
    @State fileprivate var scroll = Scroll(location: .init(lat: 49.819314, lon: 24.018401))
    @State fileprivate var scale = Scale(factor: 0.00003)
    @State fileprivate var bounds: CGSize = .init(width: 375.0, height: 700.0)
    
    @State fileprivate var newRanges: [OverpassBounds]? = nil

    init(_ coordinator: T) {
        self.coordinator = BindableCoordinator(coordinator)
    }
    
    var body: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                var anchor: OverpassPoint! = self.scroll.anchor
                if anchor == nil {
                    self.scroll.anchor = self.scroll.location
                    anchor = self.scroll.location
                }

                let translation = self.size(from: value.translation)
                self.scroll.location = .init(lat: anchor.lat + translation.lat,
                                             lon: anchor.lon - translation.lon)
        }
            .onEnded { _ in
                let previousBounds = OverpassBounds(point: self.scroll.anchor!, size: self.size(from: self.bounds))
                self.newRanges = self.overpassBounds.difference(previousBounds)
                
                self.scroll.anchor = nil
                self.coordinator.send(self.overpassBounds)
        }
        
        let pinch = MagnificationGesture()
            .onChanged { value in
                var anchor: CGFloat! = self.scale.anchor
                if anchor == nil {
                    self.scale.anchor = self.scale.factor
                    anchor = self.scale.anchor
                }
                
                self.scale.factor = anchor / value
        }
            .onEnded { _ in
                self.scale.anchor = nil
                self.coordinator.send(.arbitrary)
                self.coordinator.send(self.overpassBounds)
        }

        return VStack {
            GeometryReader { geom in
                Path { path in
                    self.bounds = geom.size

                    self.coordinator.latestResult?.relations.forEach{ relation in
                        relation.ways.forEach { way in
                            if let firstNode = way.nodes.first {
                                path.move(to: self.point(from: firstNode.location))
                            }
                            
                            for node in way.nodes {
                                path.addLine(to: self.point(from: node.location))
                                path.move(to: self.point(from: node.location))
                            }
                        }
                    }
                    
                    self.coordinator.latestResult?.ways.forEach { way in
                        if let firstNode = way.nodes.first {
                            path.move(to: self.point(from: firstNode.location))
                        }
                        
                        for node in way.nodes {
                            path.addLine(to: self.point(from: node.location))
                            path.move(to: self.point(from: node.location))
                        }
                    }
                    }.stroke(Color.white).clipped()
                }
                .clipped()
                .overlay(Rectangle()
                    .opacity(0)
                    .gesture(drag)
                    .gesture(pinch))
                .overlay(Path { path in
                    if let ranges = self.newRanges {
                        path.addRects(ranges.compactMap {
                            switch $0 {
                            case let .box(s, w, n, e):
                                return CGRect(origin: self.point(from: OverpassPoint(lat: n, lon: w)), size: self.distance(from: (n-s, e-w)))
                            default:
                                return nil
                            }
                        })
                    }
                    }
                    .fill(Color.red)
                    .opacity(0.1))
                /*
                Debug coordinate grid overlay
             
                .overlay(
                    ForEach(self.debugGrid) { (xy) -> _ModifiedContent<Text, _PositionLayout> in
                        let point = CGPoint(x: xy & 0xffff, y: xy >> 16)
                        let location = self.location(from: point)
                        
                        return Text(String(format: "%.3f;%.3f", location.lat, location.lon))
                            .font(.system(size: 8))
                            .position(point)
                        
                })
                */
        }
    }
}

fileprivate extension MapView {
    func location(from point: CGPoint) -> OverpassPoint {
        return OverpassPoint(
            lat: self.scroll.location.lat - OverpassCoordinate(point.y * self.scale.factor),
            lon: self.scroll.location.lon + OverpassCoordinate(point.x * self.scale.factor))
    }
    
    func distance(from distance: (OverpassDistance, OverpassDistance)) -> CGSize {
        return CGSize(
            width: CGFloat(distance.1) / self.scale.factor,
            height: CGFloat(distance.0) / self.scale.factor
        )
    }

    func size(from size: CGSize) -> OverpassSize {
        return OverpassSize(
            lat: OverpassCoordinate(size.height * self.scale.factor),
            lon: OverpassCoordinate(size.width * self.scale.factor)
        )
    }
    
    func point(from location: OverpassPoint) -> CGPoint {
        return CGPoint(
            x: CGFloat(location.lon - self.scroll.location.lon) / self.scale.factor,
            y: CGFloat(self.scroll.location.lat - location.lat) / self.scale.factor
        )
    }
}

fileprivate extension MapView {
    var overpassBounds: OverpassBounds {
        return OverpassBounds(point: self.scroll.location, size: self.size(from: self.bounds))
    }
}

fileprivate extension MapView {
    var debugGrid: [Int] {
        stride(from: 20, to: Int(self.bounds.height), by: 85).flatMap { (y) -> [Int] in
            stride(from: 20, to: Int(self.bounds.width), by: 75).map { (x) -> Int in
                (y << 16) ^ x
            }
        }
    }
}
