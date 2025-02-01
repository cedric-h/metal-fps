import AppKit
import MetalKit

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.finishLaunching()

let frame = NSRect(x:0, y: 0, width: 1024, height: 768)
let delegate = WindowDelegate()
let window = Window(
    contentRect: frame,
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)

let metalView = WindowView(frame: frame, device: MTLCreateSystemDefaultDevice())
metalView.colorPixelFormat = .bgra8Unorm
metalView.depthStencilPixelFormat = .depth32Float
metalView.preferredFramesPerSecond = 60
metalView.isPaused = false
metalView.enableSetNeedsDisplay = false

let renderer = Renderer(device: metalView.device!)
metalView.delegate = renderer

window.delegate = delegate
window.title = "base"
window.contentView = metalView
window.center()
window.orderFrontRegardless()
window.contentView?.updateTrackingAreas()

app.activate(ignoringOtherApps: true)

var running = true
while running {
    var event:NSEvent?

    repeat {
        event = app.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)
        
        if event != nil { app.sendEvent(event!) }
    } while event != nil
}

class WindowView: MTKView {}

class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice;

    init (device: MTLDevice) {
        self.device = device;
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        (view as! WindowView).updateTrackingAreas()
    }

    func draw(in view: MTKView) {
    }
}

class Window: NSWindow {}

class WindowDelegate : NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { running = false }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}

    func applicationWillTerminate(_ notification: Notification) {
        running = false
    }
}
