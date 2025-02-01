import AppKit
import MetalKit
import simd

var running = true
var renderer: Renderer
let app = NSApplication.shared
do {
    app.setActivationPolicy(.regular)
    app.finishLaunching()

    let frame = NSRect(x:0, y: 0, width: 1024, height: 768)
    let metalView = MTKView(frame: frame, device: MTLCreateSystemDefaultDevice())
    metalView.colorPixelFormat = .rgba8Unorm
    metalView.depthStencilPixelFormat = .depth32Float
    metalView.preferredFramesPerSecond = 60
    metalView.isPaused = false
    metalView.enableSetNeedsDisplay = false

    renderer = Renderer(
        device: metalView.device!,
        sizeX: Float(frame.width),
        sizeY: Float(frame.height)
    )
    metalView.delegate = renderer

    let windowDelegate = WindowDelegate()
    let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "lines!"
    window.delegate = windowDelegate
    window.contentView = metalView
    window.center()
    window.orderFrontRegardless()
    window.contentView?.updateTrackingAreas()

    app.activate(ignoringOtherApps: true)

    class WindowDelegate : NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) { running = false }
    }
}

var mouseX: Float = 0
var mouseY: Float = 0
while running {
    var event:NSEvent?

    repeat {
        event = app.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)
        if let e = event {

            let mouseMove = e.type == .mouseMoved ||
                            e.type == .leftMouseDragged ||
                            e.type == .rightMouseDragged
            let sameWindow = mouseMove && e.window == app.mainWindow

            if mouseMove && sameWindow {
                mouseX = Float(e.locationInWindow.x)
                mouseY = Float(e.locationInWindow.y)
            }
        }

        if event != nil { app.sendEvent(event!) }
    } while event != nil

    renderer.geo.startFrame()
    renderer.geo.drawLine(mouseX, mouseY)
}

class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice;
    var commandQueue: MTLCommandQueue
    var canvasSize: (Float, Float)

    var geo: GeoPass!

    init(device: MTLDevice, sizeX: Float, sizeY: Float) {
        self.device = device;
        self.commandQueue = device.makeCommandQueue()!
        self.canvasSize = (sizeX, sizeY)
        super.init()

        self.device.makeLibrary(source: GeoPass.shader, options: nil) { [self] lib, err in
            self.geo = GeoPass(device: device, lib: lib, err: String(describing: err))
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let canvas = view.convertFromBacking(size)
        canvasSize = (Float(canvas.width), Float(canvas.height))
    }

    func draw(in view: MTKView) {
        view.clearColor = MTLClearColorMake(0.117, 0.156, 0.196, 1.0)

        let commandBuffer = commandQueue.makeCommandBuffer()!

        var cameraTransform = matrix_identity_float4x4
        do {
            let left:   Float = 0
            let right:  Float = Float(canvasSize.0)
            let top:    Float = Float(canvasSize.1)
            let bottom: Float = 0

            let lr: Float = 1 / (left - right)
            let bt: Float = 1 / (bottom - top)
            cameraTransform[0, 0] = -2 * lr
            cameraTransform[1, 1] = -2 * bt
            cameraTransform[3, 0] = (left + right) * lr
            cameraTransform[3, 1] = (top + bottom) * bt
        }

        geo.draw(
            commandBuffer.makeRenderCommandEncoder(
                descriptor: view.currentRenderPassDescriptor!
            )!,
            transform: &cameraTransform
        )

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }

    struct GeoPass {
        var pipelineState: MTLRenderPipelineState
        var library: MTLLibrary

        var vert: MTLFunction
        var frag: MTLFunction

        var vertBuf:    MTLBuffer
        var vertBufCap: Int
        var indxBuf:    MTLBuffer
        var indxBufCap: Int

        var indxCount: Int = 0

        static let shader = """
#include <simd/simd.h>

using namespace metal;

vertex float4 vert(
    constant packed_float3 *vertices  [[ buffer(0) ]],
    constant simd_float4x4 *transform [[ buffer(1) ]],
    uint vid [[ vertex_id ]])
{
    return (*transform) * float4(vertices[vid], 1.0);
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

            vertBufCap = 1 << 10
            vertBuf = device.makeBuffer(length: 4 * vertBufCap, options: [])!
            indxBufCap = 1 << 10
            indxBuf = device.makeBuffer(length: 2 * indxBufCap, options: [])!
        }

        mutating func startFrame() {
            indxCount = 0
        }

        mutating func drawLine(_ x: Float, _ y: Float) {
            vertBuf
                .contents()
                .bindMemory(to: Float.self, capacity: vertBufCap)
                .update(
                    from: [
                        x +  10, y +  10, 0.0,
                        x +  10, y + -10, 0.0,
                        x + -10, y + -10, 0.0,
                        x + -10, y +  10, 0.0
                    ],
                    count: vertBufCap
                );


            // future performance TODO:
            // - I wonder if this array literal heap allocates?
            // - triple buffer ala https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html#//apple_ref/doc/uid/TP40016642-CH5-SW1
            indxBuf
                .contents()
                .bindMemory(to: UInt16.self, capacity: indxBufCap)
                .update(
                    from: [
                        2, 3, 1,
                        0, 1, 2
                    ],
                    count: indxBufCap
                );

            indxCount += 6
        }

        func draw(_ encoder: MTLRenderCommandEncoder, transform: inout simd_float4x4) {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
            encoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 1)

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

