//
//  ScreenManager.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 12/23/15.
//  Copyright © 2015 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Silica

public protocol ScreenManagerDelegate {
	func activeWindowsForScreenManager(screenManager: ScreenManager) -> [SIWindow]
	func windowIsActive(window: SIWindow) -> Bool
}

public class ScreenManager: NSObject {
	public var screen: NSScreen
	public let screenIdentifier: String
	private let delegate: ScreenManagerDelegate

	public var currentSpaceIdentifier: String? {
		willSet {
			guard let spaceIdentifier = currentSpaceIdentifier else {
				return
			}

			currentLayoutIndexBySpaceIdentifier[spaceIdentifier] = currentLayoutIndex
		}
		didSet {
			defer {
				setNeedsReflow()
			}

			guard let spaceIdentifier = currentSpaceIdentifier else {
				return
			}

			changingSpace = true
			currentLayoutIndex = currentLayoutIndexBySpaceIdentifier[spaceIdentifier] ?? 0

			if let layouts = layoutsBySpaceIdentifier[spaceIdentifier] {
				self.layouts = layouts
			} else {
				self.layouts = LayoutManager.layoutsWithWindowActivityCache(self)
				layoutsBySpaceIdentifier[spaceIdentifier] = layouts
			}
		}
	}
	public var isFullscreen = false

	private var reflowTimer: NSTimer?
	private var reflowOperation: ReflowOperation?

	private var layouts: [Layout] = []
	private var currentLayoutIndexBySpaceIdentifier: [String: Int] = [:]
	private var layoutsBySpaceIdentifier: [String: [Layout]] = [:]
	private var currentLayoutIndex: Int {
		didSet {
			if !self.changingSpace || UserConfiguration.sharedConfiguration.enablesLayoutHUDOnSpaceChange() {
				self.displayLayoutHUD()
			}
		}
	}
	private var currentLayout: Layout {
		return layouts[currentLayoutIndex]
	}

	private let layoutNameWindowController: LayoutNameWindowController

	private var changingSpace: Bool = false

	init(screen: NSScreen, screenIdentifier: String, delegate: ScreenManagerDelegate) {
		self.screen = screen
		self.screenIdentifier = screenIdentifier
		self.delegate = delegate

		self.currentLayoutIndexBySpaceIdentifier = [:]
		self.layoutsBySpaceIdentifier = [:]
		self.currentLayoutIndex = 0

		self.layoutNameWindowController = LayoutNameWindowController(windowNibName: "LayoutNameWindow")

		super.init()

		self.layouts = LayoutManager.layoutsWithWindowActivityCache(self)
	}

	public func setNeedsReflow() {
		reflowOperation?.cancel()

		if changingSpace {
			// The 0.4 is disgustingly tied to the space change animation time.
			// This should get burned to the ground when space changes don't rely on the mouse click trick.
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(UInt64(0.4) * NSEC_PER_SEC)), dispatch_get_main_queue()) {
				self.reflow(nil)
			}
		} else {
			dispatch_async(dispatch_get_main_queue()) {
				self.reflow(nil)
			}
		}
	}

	private func reflow(sender: AnyObject?) {
		guard
			currentSpaceIdentifier != nil &&
				currentLayoutIndex < layouts.count &&
				UserConfiguration.sharedConfiguration.tilingEnabled &&
				!isFullscreen &&
				!CGSManagedDisplayIsAnimating(_CGSDefaultConnection(), screenIdentifier)
			else {
				return
		}

		let windows = delegate.activeWindowsForScreenManager(self)
		changingSpace = false
		reflowOperation = currentLayout.reflowOperationForScreen(screen, withWindows: windows)
		NSOperationQueue.mainQueue().addOperation(reflowOperation!)
	}

	public func updateCurrentLayout(updater: (Layout) -> ()) {
		updater(currentLayout)
		setNeedsReflow()
	}

	public func cycleLayoutForward() {
		currentLayoutIndex = (currentLayoutIndex + 1) % layouts.count
		setNeedsReflow()
	}

	public func cycleLayoutBackward() {
		currentLayoutIndex = (currentLayoutIndex == 0 ? layouts.count : currentLayoutIndex) - 1
		setNeedsReflow()
	}

	public func selectLayout(layoutType: AnyClass) {
		let index = layouts.indexOf { $0.isKindOfClass(layoutType) }
		guard let layoutIndex = index else {
			return
		}

		currentLayoutIndex = layoutIndex
		setNeedsReflow()
	}

	func shrinkMainPane() {
		currentLayout.shrinkMainPane()
	}

	func expandMainPane() {
		currentLayout.expandMainPane()
	}

	public func displayLayoutHUD() {
		guard UserConfiguration.sharedConfiguration.enablesLayoutHUD() else {
			return
		}

		defer {
			NSObject.cancelPreviousPerformRequestsWithTarget(self, selector: #selector(ScreenManager.hideLayoutHUD(_:)), object: nil)
			performSelector(#selector(ScreenManager.hideLayoutHUD(_:)), withObject: nil, afterDelay: 0.6)
		}

		guard let layoutNameWindow = layoutNameWindowController.window as? LayoutNameWindow else {
			return
		}

		let screenFrame = screen.frame
		let screenCenter = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
		let windowOrigin = CGPoint(
			x: screenCenter.x - layoutNameWindow.frame.width / 2.0,
			y: screenCenter.y - layoutNameWindow.frame.height / 2.0
		)

		layoutNameWindow.layoutNameField?.stringValue = currentLayout.dynamicType.layoutName
		layoutNameWindow.setFrameOrigin(NSPointFromCGPoint(windowOrigin))

		layoutNameWindowController.showWindow(self)
	}

	public func hideLayoutHUD(sender: AnyObject) {
		layoutNameWindowController.close()
	}
}

extension ScreenManager: WindowActivityCache {
	public func windowIsActive(window: SIWindow) -> Bool {
		return delegate.windowIsActive(window)
	}
}

extension WindowManager: ScreenManagerDelegate {
    public func activeWindowsForScreenManager(screenManager: ScreenManager) -> [SIWindow] {
        return activeWindowsForScreen(screenManager.screen)
    }

    public func windowIsActive(window: SIWindow) -> Bool {
        if !window.isActive() {
            return false
        }
        if activeIDCache[window.windowID()] == nil {
            return false
        }
        return true
    }
}
