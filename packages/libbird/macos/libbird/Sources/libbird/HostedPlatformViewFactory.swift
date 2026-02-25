//
//  HostedPlatformView.swift
//  libbird
//
//  Created by Eric Apostal on 2/24/26.
//

import FlutterMacOS
import AppKit

class HostedPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemBlue.cgColor
        
        let label = NSTextField(labelWithString: "Native macOS View")
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = NSColor.clear
        label.frame = NSRect(x: 10, y: 10, width: 150, height: 30)
        
        view.addSubview(label)
        
        return view
    }
}
