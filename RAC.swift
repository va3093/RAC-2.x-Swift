//
//  RAC.swift
//  Tag
//
//  Created by Wilhelm Van Der Walt on 4/18/15.
//  Copyright (c) 2015 Wilhelm Van Der Walt. All rights reserved.
//

import Foundation


protocol ISubscriber {
	typealias Element
 
	func sendNext(e: Element)
	func sendError(e: NSError)
	func sendCompleted()
}

class Subscriber<P: AnyObject> : ISubscriber {
	let subscriber: RACSubscriber
	
	init(wrapped: RACSubscriber)
	{
		subscriber = wrapped
	}
 
	func sendNext(e: P)
	{
		subscriber.sendNext(e)
	}
 
	func sendError(e: NSError)
	{
		subscriber.sendError(e)
	}
 
	func sendCompleted()
	{
		subscriber.sendCompleted()
	}
}

class Signal<T: AnyObject> {
	let signal: RACSignal
 
	init(wrapped: RACSignal)
	{
		signal = wrapped
	}
	
	convenience init(didSubscribe:( (Subscriber<T>) -> RACDisposable!))
	{
		self.init(wrapped: RACSignal.createSignal { (racSubscriber: RACSubscriber!) -> RACDisposable! in
			let subscriber = Subscriber<T>(wrapped: racSubscriber)
			return didSubscribe(subscriber)
			})
	}
	
	class func empty() -> Signal<T> {
		return Signal(didSubscribe: { (subscriber: Subscriber<T>) -> RACDisposable! in
			subscriber.sendCompleted()
			return nil
		})
	}
	
	class func combineLatest(signals: [RACSignal]) -> Signal<RACTuple> {
		return Signal<RACTuple>(wrapped: RACSignal.combineLatest(signals))
	}
	
	class func mergeTypeSafe(signals: [Signal<T>]) -> Signal<T> {
		return Signal<T>(wrapped: RACSignal.merge(signals.map({$0.signal})))
	}
	
	func subscribeNext(next:( (object: T) -> Void)) -> RACDisposable
	{
		return self.signal.subscribeNext { value in
			if let nextValue = value as? T {
				next(object: nextValue)
			} else {
				assert(false, "got a \(value) while we were expecting \(T.self)")
			}

		}
	}
	
	//Mark: Operations
	
	func distinctUntilChanged() -> Signal<T> {
		return Signal<T>(wrapped: self.signal.distinctUntilChanged().filter({ (object: AnyObject!) -> Bool in
			if let obj: T = object as? T {
				return true
			}
			assert(false, "got a \(object) while we were expecting \(T.self)")
			return false
		}))
	}
	
	func logAll() -> Signal<T> {
		return Signal<T>(wrapped: self.signal.logAll())
	}
	
	func doNext(closure:((object: T) -> Void)!) -> Signal<T>
	{
		let typeSafeClosure = {(object: AnyObject!) -> Void in
			if let obj: T = object as? T {
				return closure(object: obj)
			}
			assert(false, "got a \(object) while we were expecting \(T.self)")

		}

		return Signal<T>(wrapped: self.signal.doNext(typeSafeClosure))

	}
	
	func doCompleted(closure:(() -> Void)!) -> Signal<T>
	{
		return Signal<T>(wrapped: self.signal.doCompleted(closure))
	}
	
	func map<U: AnyObject>(type: U.Type, closure: ((object: T) -> U) ) -> Signal<U> {
		let typeSafeClosure = {(object: AnyObject!) -> AnyObject! in
			if let obj1: T = object as? T {
				return closure(object: obj1)
			}
			assert(false, "got a \(object) while we were expecting \(T.self)")
		}
		return Signal<U>(wrapped: self.signal.map(typeSafeClosure))
	}
	
	func flattenMap<U: AnyObject>(type: U.Type, closure: ((object: T) -> Signal<U>)) -> Signal<U> {
		return Signal<U>(wrapped: self.signal.flattenMap({ (object: AnyObject!) -> RACStream! in
			if let obj: T = object as? T {
				return closure(object: obj).signal
			}
			assert(false, "got a \(object) while we were expecting \(T.self)")
			return Signal<U>.empty().signal
		}))
	}
	
	func filter(closure: (object: T) -> Bool) -> Signal<T> {
		let typeSafeClosure = {(object: AnyObject!) -> Bool in
			if let obj: T = object as? T {
				return closure(object: obj)
			}
			assert(false, "got a \(object) while we were expecting \(T.self)")
			return false
		}
		return Signal<T>(wrapped: self.signal.filter(typeSafeClosure))

	}
	
	func sample<U: AnyObject>(signal: Signal<U>) -> Signal<T> {
		return Signal<T>(wrapped: self.signal.sample(signal.signal).filter({ (object: AnyObject!) -> Bool in
			return object is T
		}))
	}
	
	func take(count: UInt) -> Signal<T> {
		return Signal<T>(wrapped: self.signal.take(count).filter({ (object: AnyObject!) -> Bool in
			return object is T
		}))
	}
	
	func switchToLatest<U: AnyObject>(type: U.Type) -> Signal<U> {
		
		return Signal<U>(wrapped: self.signal.map({ (object: AnyObject!) -> AnyObject! in
			if let sig : Signal<U> = object as? Signal<U> {
				return sig.signal
			}
			else {
				return nil
			}
		}).switchToLatest().filter({ (object: AnyObject!) -> Bool in
			if  object is U {
				return true
			}
			else {
				assert(false, "got a \(object) while we were expecting \(U.self)")
			}
		}))
	}
	
	func replayLast() -> Signal<T> {
		return Signal<T>(wrapped: self.signal.replayLast().filter({ (object: AnyObject!) -> Bool in
			return object is T
		}))
	}
	
	func then<U: AnyObject>(block: (() -> Signal<U>)) -> Signal<U> {
		let typeSafeClosure = {() -> RACSignal! in
			return block().signal
		}
		return Signal<U>(wrapped: self.signal.then(typeSafeClosure))
	}
	
	func startWith(object: T) -> Signal<T> {
		return Signal<T>(wrapped: self.signal.startWith(object).filter({ (object: AnyObject!) -> Bool in
			return object is T
		}))
	}
	
}



class Subject<T: AnyObject>: Signal<T>  {
	
	init() {
		super.init(wrapped: RACSubject() )
	}
	
	func sendNext(object: T) {
		(self.signal as? RACSubject)?.sendNext(object)
	}
	
	func sendCompleted() {
		(self.signal as? RACSubject)?.sendCompleted()
	}
	
}


class Command<U: AnyObject, T: AnyObject> {
	let rac_command: RACCommand
	
	init(wrappedCommand: RACCommand) {
		self.rac_command = wrappedCommand
	}
	
	convenience init(signalBlock:((object: U) -> Signal<T>)) {
		let typeSafeClosure = {(object: AnyObject!) -> RACSignal! in
			if let obj: U = object as? U {
				return signalBlock(object: obj).signal
			}
			else {
				assert(false, "got a \(object) while we were expecting \(U.self)")
				return RACSignal.empty()
			}
		}
		self.init(wrappedCommand: RACCommand(signalBlock: typeSafeClosure))
	}
	
	func execute(object: U) {
		self.rac_command.execute(object)
	}
	
	func executionSignals() -> Signal<Signal<T>> {
		let signal: Signal<RACSignal> = Signal<RACSignal>(wrapped: self.rac_command.executionSignals)
		return signal.map(Signal<T>.self, closure: { (object: RACSignal) -> Signal<T> in
			return Signal<T>(wrapped: object)
		})
			
	}
}



extension NSNotificationCenter {
	
	func rac_addObserverForName<T: AnyObject>(name: String, sendingObject: T) -> Signal<T> {
		return Signal<T>(wrapped: self.rac_addObserverForName(name, object: sendingObject).filter({ (object: AnyObject!) -> Bool in
			return object is T
		}))
	}
}



