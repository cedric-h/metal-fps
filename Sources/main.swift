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
metalView.colorPixelFormat = .rgba8Unorm
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
    var commandQueue: MTLCommandQueue

    var pipelineState: MTLRenderPipelineState!
    var library: MTLLibrary!

    var vert: MTLFunction!
    var frag: MTLFunction!
    var vertBuf: MTLBuffer!

    init(device: MTLDevice) {
        self.device = device;
        self.commandQueue = device.makeCommandQueue()!
        super.init()

        let shader = """
#include <simd/simd.h>

using namespace metal;

vertex float4 vert(
    constant packed_float3 *vertices  [[ buffer(0) ]],
    uint vid [[ vertex_id ]])
{
    return float4(vertices[vid], 1.0);
}

fragment float4 frag() // (float4 vert [[stage_in]])
{
    return float4(0.7, 1, 1, 1);
}
"""

        self.device.makeLibrary(source: shader, options: nil) { [self] lib, err in
            if lib == nil {
                fatalError("Invalid shaders: \(String(describing:err))")
            }
            self.library = lib!

            vert = library.makeFunction(name: "vert")
            frag = library.makeFunction(name: "frag")

            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vert
            pipelineStateDescriptor.fragmentFunction = frag
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)

            let vertexData: [Float] = [
                 0.0,  1.0, 0.0,
                -0.9, -1.0, 0.0,
                 0.9, -1.0, 0.0
            ]
            vertBuf = device.makeBuffer(
                bytes: vertexData,
                length: 4 * 9,
                options: []
            )

        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        (view as! WindowView).updateTrackingAreas()
    }

    func draw(in view: MTKView) {
        view.clearColor = MTLClearColorMake(0.117, 0.156, 0.196, 1.0)

        let commandBuffer = commandQueue.makeCommandBuffer()!

        if true {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: view.currentRenderPassDescriptor!
            )!

            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertBuf, offset: 0, index: 0)

            renderEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 3,
                instanceCount: 1
            )

            renderEncoder.endEncoding()
        }

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
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
