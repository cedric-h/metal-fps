import AppKit
import MetalKit
import simd

let WALL_HEIGHT: Float = 3.15

var running = true
var renderer: Renderer
let app = NSApplication.shared
do {
    app.setActivationPolicy(.regular)
    app.finishLaunching()

    let frame = NSRect(x:0, y: 0, width: 1600, height: 900)
    let metalView = MTKView(frame: frame, device: MTLCreateSystemDefaultDevice())
    metalView.colorPixelFormat = .rgba8Unorm
    metalView.depthStencilPixelFormat = .depth32Float
    metalView.isPaused = false
    metalView.enableSetNeedsDisplay = false

    renderer = Renderer(
        device: metalView.device!,
        sizeX: Float(frame.width),
        sizeY: Float(frame.height)
    )
    metalView.delegate = renderer

    let windowDelegate = WindowDelegate()
    let window = Window(
        contentRect: frame,
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Postal 5: Killrock"
    window.delegate = windowDelegate
    window.contentView = metalView
    window.center()
    window.orderFrontRegardless()
    window.contentView?.updateTrackingAreas()

    app.activate(ignoringOtherApps: true)

    class WindowDelegate : NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) { running = false }
    }
    class Window : NSWindow {
        // this prevents the "beep" sound on keydown
        override func keyDown(with event:NSEvent) {}
    }
}

struct Camera {
    var pitch: Float = Float.pi * 0.98
    var yaw: Float = 0
    var pos = simd_float3(8, 27, 1.7)

    var dir: simd_float3 {
        get { simd_float3(sin(yaw) * cos(pitch), cos(yaw) * cos(pitch), sin(pitch)) }
    }
}
var camera = Camera()

var keysDown = [Bool](repeating: false, count: 100)
let zones = getZones()
while running {
    var event:NSEvent?

    repeat {
        event = app.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)
        if let e = event {
            let mouseMove = e.type == .mouseMoved ||
                            e.type == .leftMouseDragged ||
                            e.type == .rightMouseDragged

            if mouseMove && e.pressure > 0 {
                camera.pitch += Float(e.deltaY) * 0.003
                camera.yaw += Float(e.deltaX) * 0.003
            }

            repeat {
                if e.type != .flagsChanged && e.type != .keyDown && e.type != .keyUp { continue }

                let code = Int(e.keyCode)
                if !(0..<keysDown.count).contains(code) { continue }

                keysDown[code] = e.type == .keyDown
                keysDown[56] = e.modifierFlags.contains(.shift)
                if code == 53 { running = false }
            } while false
        }

        if event != nil { app.sendEvent(event!) }
    } while event != nil

    guard renderer.geo != nil else { continue }

    // using keycodes rather than e.characters because
    // keycodes should correspond to locations and thusly be keyboard-layout independent
    do {
        var forwards: Float = 0
        var sideways: Float = 0
        var jump:     Float = 0
        if keysDown[13] { forwards += 1 }
        if keysDown[1 ] { forwards -= 1 }
        if keysDown[0 ] { sideways -= 1 }
        if keysDown[2 ] { sideways += 1 }
        if keysDown[49] { jump += 1 }
        if keysDown[56] { jump -= 1 }

        let up = simd_float3(0, 0, 1)
        camera.pos += camera.dir * forwards * 0.001
        camera.pos += cross(camera.dir, up) * sideways * 0.001
        camera.pos += jump * up * 0.001
    }

    renderer.geo!.frameStart()
    for shape in zones {
        var from = shape[0]

        for point in shape[1...] {
            renderer.geo!.drawWall(
                from.x, from.y,
                point.x, point.y,
                height: WALL_HEIGHT
            )
            from = point
        }

        renderer.geo!.drawWall(
            from.x, from.y,
            shape[0].x, shape[0].y,
            height: WALL_HEIGHT
        )
    }
    renderer.geo!.frameEnd()
}
class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var canvasSize: (Float, Float)

    var geo: GeoPass?

    init(device: MTLDevice, sizeX: Float, sizeY: Float) {
        self.device = device
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
        view.clearDepth = 1.0

        let commandBuffer = commandQueue.makeCommandBuffer()!

        var cameraTransform = matrix_identity_float4x4
        do {
            let ortho = false

            let near:   Float = 0.01
            let far:    Float =  100

            if false && ortho {
                let zoom: Float = 0.1
                let cameraX: Float = -48.5
                let cameraY: Float = -36

                let left:   Float = cameraX
                let right:  Float = cameraX + Float(canvasSize.0)*zoom
                let top:    Float = cameraY + Float(canvasSize.1)*zoom
                let bottom: Float = cameraY

                let lr: Float = 1.0 / (left - right)
                let bt: Float = 1.0 / (bottom - top)
                let nf: Float = 1.0 / (near - far)
                cameraTransform[0, 0] = -2 * lr
                cameraTransform[1, 1] = -2 * bt
                cameraTransform[2, 2] = nf
                cameraTransform[3, 0] = (left + right) * lr
                cameraTransform[3, 1] = (top + bottom) * bt
                cameraTransform[3, 2] = near * nf
            } else {
                let fieldOfView: Float = 45 / 180 * Float.pi
                let aspect: Float = canvasSize.0 / canvasSize.1
                let yScale = 1 / tan(fieldOfView * 0.5)
                let xScale = yScale / aspect
                let zRange = far - near
                let zScale = -(far + near) / zRange
                let wzScale = -2 * far * near / zRange
                cameraTransform[0] = [xScale, 0, 0, 0]
                cameraTransform[1] = [0, yScale, 0, 0]
                cameraTransform[2] = [0, 0, zScale, -1]
                cameraTransform[3] = [0, 0, wzScale, 0]
            }

            var targeted = matrix_identity_float4x4
            do {
                let eye    = camera.pos
                let target = camera.pos + camera.dir
                let up     = simd_float3(0, 0, 1)

                // Make a matrix where the forward vector is oriented
                // directly at the target; get orthonormal bases for the others
                let z = normalize(eye - target)
                let x = normalize(cross(up, z))
                targeted[0] = simd_float4(x, 0)
                targeted[1] = simd_float4(cross(z, x), 0)
                targeted[2] = simd_float4(z, 0)
                targeted[3] = simd_float4(eye, 1)
            }
            cameraTransform *= targeted.inverse
        }

        geo?.draw(
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
        var depthState: MTLDepthStencilState
        var library: MTLLibrary

        var vert: MTLFunction
        var frag: MTLFunction

        var vertBuf:    MTLBuffer
        var vertBufCap: Int
        var indxBuf:    MTLBuffer
        var indxBufCap: Int

        var vertCount: Int = 0
        var indxCount: Int = 0

        static let shader = """
#include <simd/simd.h>

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float height;
};

vertex VertexOut vert(
    constant packed_float3 *vertices  [[ buffer(0) ]],
    constant simd_float4x4 *transform [[ buffer(1) ]],
    uint vid [[ vertex_id ]]
) {
    VertexOut out;
    out.position = (*transform) * float4(vertices[vid], 1.0);
    out.height = vertices[vid].z / \(WALL_HEIGHT);
    return out;
}

fragment float4 frag(VertexOut v [[stage_in]]) {
    return float4(0.7, v.height, 1, 1);
}
"""

        init(device: MTLDevice, lib: MTLLibrary?, err: String) {
            if lib == nil {
                fatalError("Invalid GeoPass shaders: \(err)")
            }
            self.library = lib!

            vert = library.makeFunction(name: "vert")!
            frag = library.makeFunction(name: "frag")!

            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .lessEqual
            depthDescriptor.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!

            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vert
            pipelineStateDescriptor.fragmentFunction = frag
            pipelineStateDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)

            vertBufCap = 1 << 20
            vertBuf = device.makeBuffer(length: 4 * vertBufCap, options: [])!
            indxBufCap = 1 << 20
            indxBuf = device.makeBuffer(length: 2 * indxBufCap, options: [])!
        }

        mutating func frameStart() {
            indxCount = 0
            vertCount = 0
        }

        mutating func frameEnd() {
            vertBuf.didModifyRange(0..<(4 * vertCount))
            indxBuf.didModifyRange(0..<(2 * indxCount))
        }

        mutating func drawWall(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, height: Float) {
            let startIndex = UInt16(vertCount / 3)
            // future performance TODO:
            // - I wonder if this array literal heap allocates?
            // - triple buffer ala https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html#//apple_ref/doc/uid/TP40016642-CH5-SW1
            (vertBuf.contents() + vertCount * MemoryLayout<Float>.size)
                .bindMemory(to: Float.self, capacity: vertBufCap)
                .update(
                    from: [
                        x0, y0, 0 + height,
                        x0, y0, 0,
                        x1, y1, 0 + height,
                        x1, y1, 0
                    ],
                    count: 12
                )
            vertCount += 12


            (indxBuf.contents() + indxCount * MemoryLayout<UInt16>.size)
                .bindMemory(to: UInt16.self, capacity: indxBufCap)
                .update(
                    from: [
                        startIndex + 0, startIndex + 1, startIndex + 2,
                        startIndex + 2, startIndex + 3, startIndex + 1
                    ],
                    count: 6
                )

            indxCount += 6
        }

        func draw(_ encoder: MTLRenderCommandEncoder, transform: inout simd_float4x4) {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
            encoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 1)

            encoder.setDepthStencilState(depthState)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indxCount,
                indexType: .uint16,
                indexBuffer: indxBuf,
                indexBufferOffset: 0
            )

            encoder.endEncoding()
        }
    }
}

func getZones() -> [[simd_float2]] {
    typealias v2 = simd_float2
    return [
        [v2(-13.7222, 9.3124), v2(-13.7222, 3.2280), v2(-9.8044, 3.2280), v2(-9.8044, 9.3124)],
        [v2(20.2308, 0.9308), v2(20.2308, -2.2550), v2(24.0808, -2.2550), v2(24.0808, 0.9308)],
        [v2(26.4385, 20.4308), v2(26.4385, 16.4623), v2(31.3808, 16.4623), v2(31.3808, 20.4308)],
        [v2(-14.5304, -23.6692), v2(-14.5304, -25.5808), v2(-12.6173, -25.5808), v2(-12.6173, -23.6692)],
        [v2(1.6308, -14.3000), v2(1.6308, -18.1692), v2(7.9696, -18.1692), v2(7.9696, -14.3000)],
        [v2(-10.1944, -0.3313), v2(-10.1944, -2.0082), v2(-7.3504, -2.0082), v2(-7.3504, -0.3313)],
        [v2(20.2308, 9.8270), v2(20.2308, 7.2808), v2(21.5607, 7.2808), v2(21.5607, 9.8270)],
        [v2(26.4385, 16.4623), v2(26.4385, 13.3308), v2(31.3808, 13.3308), v2(31.3808, 16.4623)],
        [v2(8.1047, -10.6565), v2(8.1047, -13.8192), v2(10.9578, -13.8192), v2(10.9578, -10.6565)],
        [v2(-17.8192, -19.8809), v2(-17.8192, -24.4192), v2(-14.5304, -24.4192), v2(-14.5304, -19.8809)],
        [v2(-2.0749, -14.3013), v2(7.8808, -14.3013), v2(7.8808, -11.4790), v2(-2.0749, -11.4790), v2(-2.0749, -14.3013)],
        [v2(30.9885, 1.3808), v2(31.0507, 2.8878), v2(30.9885, 4.3308), v2(26.4385, 4.3308), v2(26.4385, 1.3808)],
        [v2(26.4385, 13.3308), v2(26.4385, 7.4308), v2(31.3808, 7.4308), v2(31.3808, 13.3308)],
        [v2(-1.9654, 13.4359), v2(-1.4359, 13.9693), v2(-3.0972, 15.6185), v2(-3.5936, 15.6167), v2(-3.5936, 16.2464), v2(-4.8000, 16.1000), v2(-6.0022, 15.6656), v2(-7.0080, 15.1556), v2(-7.8993, 14.5237), v2(-8.6997, 13.7375), v2(-9.3192, 12.8447), v2(-9.8188, 11.8322), v2(-10.1304, 10.7768), v2(-10.2721, 9.6861), v2(-10.2721, 9.3808), v2(-9.1614, 9.3808), v2(-6.4042, 6.6236), v2(-0.7743, 12.2535)],
        [v2(8.1047, -7.4807), v2(8.1047, -10.6565), v2(10.9578, -10.6565), v2(10.9578, -7.4807)],
        [v2(25.6527, 23.9308), v2(25.6527, 20.3669), v2(30.2308, 20.3669), v2(30.2308, 23.9308)],
        [v2(-24.3192, 8.1048), v2(-24.3192, 3.1155), v2(-17.3170, 3.1155), v2(-17.3170, 8.1048)],
        [v2(-14.5304, -21.7692), v2(-14.5304, -23.6692), v2(-12.6173, -23.6692), v2(-12.6173, -21.7692)],
        [v2(7.8808, -6.5192), v2(-1.9692, -6.5192), v2(-1.9692, -8.8290), v2(0.0155, -8.8290), v2(0.0155, -11.4790), v2(7.8808, -11.4790)],
        [v2(-10.1944, -15.6497), v2(-10.1944, -17.6046), v2(-8.1283, -17.6046), v2(-8.1283, -15.6497)],
        [v2(-1.6192, -18.2209), v2(-1.6192, -14.2979), v2(-3.9692, -14.2979), v2(-3.9692, -17.6025), v2(-10.1944, -17.6025), v2(-10.1944, -0.3292), v2(-7.3504, -0.3292), v2(-3.4136, 3.6077), v2(-6.4765, 6.6706), v2(-9.8044, 3.3427), v2(-17.3170, 3.3427), v2(-17.3170, 3.1176), v2(-24.3188, 3.1176), v2(-24.3188, -1.0897), v2(-24.3188, -2.9192), v2(-25.4692, -2.9192), v2(-25.4692, -14.7171), v2(-24.3192, -14.7171), v2(-24.3192, -19.8788), v2(-12.6173, -19.8788), v2(-12.6173, -25.5787), v2(-1.6192, -25.5787), v2(-1.6192, -20.1671), v2(7.5084, -20.1671), v2(7.5084, -18.2209)],
        [v2(-8.1283, -15.6497), v2(-8.1283, -17.6046), v2(-6.0692, -17.6046), v2(-6.0692, -15.6497)],
        [v2(13.9808, 20.3669), v2(13.9808, 16.5937), v2(17.2308, 16.5937), v2(17.2308, 20.3669)],
        [v2(20.4808, -22.0616), v2(20.4808, -24.4192), v2(22.8188, -24.4192), v2(22.8188, -22.0616)],
        [v2(27.0732, -19.7185), v2(27.5754, -18.7510), v2(27.8609, -17.7096), v2(27.9032, -17.0911), v2(25.4964, -14.6543), v2(22.9806, -17.0174), v2(26.3977, -20.5858)],
        [v2(25.6527, 30.0808), v2(25.6527, 23.9308), v2(30.2308, 23.9308), v2(30.2308, 30.0808)],
        [v2(26.7203, -14.7192), v2(26.7203, -15.8192), v2(27.9477, -17.0466), v2(30.2308, -17.0466), v2(30.2308, -14.7192)],
        [v2(20.2308, 7.2808), v2(20.2308, 4.0808), v2(24.0808, 4.0808), v2(24.0808, 7.2808)],
        [v2(-17.3170, 8.1048), v2(-17.3170, 3.3406), v2(-13.7222, 3.3406), v2(-13.7222, 8.1048)],
        [v2(17.3449, 8.0022), v2(7.5503, 8.0022), v2(7.5503, 7.4101), v2(0.4515, 7.4101), v2(-3.5592, 3.3994), v2(-1.9654, 1.8057), v2(-1.9654, -3.9851), v2(7.5503, -3.9851), v2(8.0062, -4.4411), v2(10.3359, -2.1114), v2(9.6917, -1.4671), v2(9.6917, 0.1329), v2(11.1917, 0.1329), v2(11.1917, 3.8829), v2(9.6917, 3.8829), v2(9.6917, 5.4829), v2(10.1308, 5.9220), v2(17.3449, 5.9220)],
        [v2(-3.1389, 15.6599), v2(-1.4359, 13.9693), v2(-1.9654, 13.4359), v2(-0.7831, 12.2622), v2(2.6107, 15.6810)],
        [v2(26.4385, 7.4308), v2(24.1308, 7.4308), v2(24.1308, -2.2575), v2(16.4911, -2.2575), v2(16.4911, -5.1120), v2(13.3294, -5.1120), v2(10.3397, -2.1223), v2(7.9696, -4.4925), v2(10.9592, -7.4821), v2(10.9592, -13.8192), v2(8.1047, -13.8192), v2(8.1047, -18.2231), v2(7.5084, -18.2231), v2(7.5084, -25.5808), v2(20.4808, -25.5808), v2(20.4980, -19.4980), v2(25.4632, -14.5368), v2(26.7203, -14.5368), v2(26.7203, -14.7192), v2(31.3808, -14.7192), v2(31.3808, -1.6692), v2(26.4385, -1.6692)],
        [v2(21.5607, 9.8270), v2(21.5607, 7.2808), v2(24.0808, 7.2808), v2(24.0808, 9.8270)],
        [v2(13.3294, -2.2575), v2(13.3294, -5.1120), v2(16.4911, -5.1120), v2(16.4911, -2.2575)],
        [v2(17.3449, 5.9220), v2(10.1308, 5.9220), v2(9.7381, 5.4048), v2(9.7381, 3.8829), v2(11.2308, 3.8829), v2(11.2308, 2.0079), v2(17.3449, 2.0079)],
        [v2(10.7753, 20.3669), v2(10.7753, 16.5937), v2(13.9808, 16.5937), v2(13.9808, 20.3669)],
        [v2(-0.7743, -6.5192), v2(-0.7743, -3.9692), v2(-1.9704, -3.9692), v2(-1.9704, -6.5192)],
        [v2(20.2308, -2.2550), v2(20.2308, 7.9308), v2(17.3449, 7.9308), v2(17.3449, -2.2550)],
        [v2(6.2226, 20.3669), v2(6.2226, 16.5937), v2(10.7753, 16.5937), v2(10.7753, 20.3669)],
        [v2(-3.9692, -14.2979), v2(-2.0749, -14.3013), v2(-2.0749, -11.4790), v2(0.0155, -11.4790), v2(0.0155, -8.8290), v2(-1.9692, -8.8290), v2(-1.9692, -2.0082), v2(-3.9692, -2.0082)],
        [v2(-6.0692, -15.6497), v2(-6.0692, -17.6046), v2(-3.9692, -17.6046), v2(-3.9692, -15.6497)],
        [v2(-5.7296, -1.9783), v2(-2.0010, -2.0082), v2(-1.9704, 1.8057), v2(-3.5489, 3.4097), v2(-7.3504, -0.3313)],
        [v2(-21.0192, -19.8809), v2(-21.0192, -24.4192), v2(-17.8192, -24.4192), v2(-17.8192, -19.8809)],
        [v2(8.1047, -5.5114), v2(8.1047, -7.4692), v2(10.9330, -7.4692), v2(8.9752, -5.5114)],
        [v2(-0.7743, -3.9851), v2(-0.7743, -6.5192), v2(7.9696, -6.5192), v2(7.9696, -4.4925), v2(7.4623, -3.9851)],
        [v2(-2.2192, 30.0808), v2(-2.2192, 23.1308), v2(2.7308, 23.1308), v2(2.7308, 30.0808)],
        [v2(30.9885, 4.3308), v2(30.7160, 5.8241), v2(30.2348, 7.4308), v2(26.5056, 7.4301), v2(26.5061, 4.3300), v2(27.3136, 4.3302)],
        [v2(-14.5304, -19.8809), v2(-14.5304, -21.7692), v2(-12.6173, -21.7692), v2(-12.6173, -19.8809)],
        [v2(17.2308, 20.3669), v2(17.2308, 16.5937), v2(21.9308, 16.5937), v2(21.9308, 20.3669)],
        [v2(-10.1944, -2.0082), v2(-10.1944, -15.6497), v2(-3.9692, -15.6497), v2(-3.9692, -2.0082)],
        [v2(7.5084, -20.1656), v2(-1.6192, -20.1656), v2(-1.6192, -24.4192), v2(0.0155, -24.8692), v2(1.4808, -25.1192), v2(2.9423, -25.2289), v2(4.4371, -25.1322), v2(5.9308, -24.8692), v2(7.5084, -24.4192)],
        [v2(21.9308, 16.5937), v2(6.1808, 16.5937), v2(6.1808, 7.4308), v2(7.5808, 7.4308), v2(7.5808, 7.9904), v2(20.2308, 7.9904), v2(20.2308, 9.8270), v2(21.9308, 9.8270)],
        [v2(-9.1204, 9.3124), v2(-9.8044, 9.3124), v2(-9.8044, 3.3406), v2(-6.4765, 6.6685)],
        [v2(11.1917, 2.0079), v2(11.1917, 0.1329), v2(9.7381, 0.1329), v2(9.7381, -1.4207), v2(10.4865, -2.1692), v2(17.3449, -2.1692), v2(17.3449, 2.0079)],
        [v2(-3.4192, 19.5308), v2(-3.4192, 15.6808), v2(2.5734, 15.6808), v2(2.5734, 19.5308)],
        [v2(-2.2192, 23.1308), v2(-2.2192, 19.5308), v2(2.5734, 19.5308), v2(2.5734, 23.1308)],
        [v2(26.4385, 20.3669), v2(25.6498, 20.3669), v2(25.6498, 30.0808), v2(20.4808, 30.0808), v2(20.4808, 31.2308), v2(7.5084, 31.2308), v2(7.5084, 30.0808), v2(2.7308, 30.0808), v2(2.7308, 23.1308), v2(2.6531, 23.1308), v2(2.6531, 15.6808), v2(-6.4179, 6.6099), v2(-3.4040, 3.5960), v2(0.4308, 7.4308), v2(6.1808, 7.4308), v2(6.1808, 20.3669), v2(21.9308, 20.3669), v2(21.9308, 9.7385), v2(24.1308, 9.7385), v2(24.1308, 7.4308), v2(26.4385, 7.4308)],
        [v2(13.3294, -5.1120), v2(13.3294, -2.2192), v2(11.3794, -2.2192), v2(11.3794, -3.1620)],
        [v2(30.2308, -1.6692), v2(30.2308, -1.6692), v2(30.6808, -0.1442), v2(30.9885, 1.3808), v2(26.4385, 1.3808), v2(26.4385, -1.6692)],
        [v2(20.4808, -22.0616), v2(22.8808, -22.0616), v2(23.5382, -22.0205), v2(24.5744, -21.7515), v2(25.5608, -21.2534), v2(26.3977, -20.5858), v2(22.9720, -17.0280), v2(20.4980, -19.4980)],
        [v2(20.2308, 4.0808), v2(20.2308, 0.9308), v2(24.0808, 0.9308), v2(24.0808, 4.0808)],
        [v2(-1.5997, -14.3000), v2(-1.5997, -18.2231), v2(1.6308, -18.2231), v2(1.6308, -14.3000)],
        [v2(-24.3192, -19.8809), v2(-24.3192, -24.4192), v2(-21.0192, -24.4192), v2(-21.0192, -19.8809)]
    ]
}
