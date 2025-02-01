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

class WindowView: MTKView {
    override func mouseDragged(with event: NSEvent) {
        print(#function, event)
        super.mouseDragged(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        print(#function, event)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        print(#function, event)
        super.mouseUp(with: event)
    }
}

class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice;
    var commandQueue: MTLCommandQueue

    var geoPass: GeoPass!

    init(device: MTLDevice) {
        self.device = device;
        self.commandQueue = device.makeCommandQueue()!
        super.init()

        self.device.makeLibrary(source: GeoPass.shader, options: nil) { [self] lib, err in
            self.geoPass = GeoPass(device: device, lib: lib, err: String(describing: err))
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        (view as! WindowView).updateTrackingAreas()
    }

    func draw(in view: MTKView) {
        view.clearColor = MTLClearColorMake(0.117, 0.156, 0.196, 1.0)

        let commandBuffer = commandQueue.makeCommandBuffer()!

        geoPass.draw(
            commandBuffer.makeRenderCommandEncoder(
                descriptor: view.currentRenderPassDescriptor!
            )!
        )

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }

    struct GeoPass {
        var pipelineState: MTLRenderPipelineState
        var library: MTLLibrary

        var vert: MTLFunction
        var frag: MTLFunction
        var vertBuf: MTLBuffer
        var indxBuf: MTLBuffer

        static let shader = """
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

        init(device: MTLDevice, lib: MTLLibrary?, err: String) {
            if lib == nil {
                fatalError("Invalid GeoPass shaders: \(err)")
            }
            self.library = lib!

            vert = library.makeFunction(name: "vert")!
            frag = library.makeFunction(name: "frag")!

            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vert
            pipelineStateDescriptor.fragmentFunction = frag
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)

            let vertData: [Float] = [
                 0.5,  0.5, 0.0,
                 0.5, -0.5, 0.0,
                -0.5, -0.5, 0.0,
                -0.5,  0.5, 0.0
            ]
            vertBuf = device.makeBuffer(
                bytes: vertData,
                length: 4 * 3 * 4,
                options: []
            )!

            let indxData: [UInt16] = [
                2, 3, 1,
                0, 1, 2
            ]
            indxBuf = device.makeBuffer(
                bytes: indxData,
                length: 2 * 6,
                options: []
            )!
        }

        func draw(_ encoder: MTLRenderCommandEncoder) {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)

            encoder.drawIndexedPrimitives(
                type: .triangleStrip,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: indxBuf,
                indexBufferOffset: 0
            )

            encoder.endEncoding()
        }
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
