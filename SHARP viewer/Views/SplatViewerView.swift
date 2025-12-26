import SwiftUI
import MetalKit
import UniformTypeIdentifiers

struct SplatViewerView: View {
    @EnvironmentObject var appState: AppState
    let project: Project
    
    @State private var cameraDistance: Float = 3.0
    @State private var cameraRotationX: Float = 0.0
    @State private var cameraRotationY: Float = 0.0
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            MetalSplatView(
                plyURL: project.outputPLYURL,
                cameraDistance: $cameraDistance,
                cameraRotationX: $cameraRotationX,
                cameraRotationY: $cameraRotationY
            )
            .gesture(dragGesture)
            .gesture(magnificationGesture)
            
            VStack {
                Spacer()
                
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(duration: 0.5)) {
                                cameraDistance = 3.0
                                cameraRotationX = 0
                                cameraRotationY = 0
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(Circle())
                        .help("Reset View")
                        
                        Button {
                            exportPLY()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(Circle())
                        .help("Export PLY")
                        
                        Button {
                            shareProject()
                        } label: {
                            Image(systemName: "paperplane")
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(Circle())
                        .help("Share")
                    }
                }
                .padding(.bottom, 24)
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(project.name)
                            .font(.headline)
                        Text("\(Int(cameraDistance * 100))% zoom")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                
                Spacer()
            }
        }
        .navigationTitle(project.name)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                cameraRotationY += Float(value.translation.width) * 0.01
                cameraRotationX += Float(value.translation.height) * 0.01
                cameraRotationX = max(-Float.pi / 2, min(Float.pi / 2, cameraRotationX))
            }
            .onEnded { _ in
                isDragging = false
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newDistance = cameraDistance / Float(value)
                cameraDistance = max(0.5, min(10, newDistance))
            }
    }
    
    private func exportPLY() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ply")!]
        panel.nameFieldStringValue = "\(project.name).ply"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.copyItem(at: project.outputPLYURL, to: url)
        }
    }
    
    private func shareProject() {
        let picker = NSSharingServicePicker(items: [project.outputPLYURL])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}

struct MetalSplatView: NSViewRepresentable {
    let plyURL: URL
    @Binding var cameraDistance: Float
    @Binding var cameraRotationX: Float
    @Binding var cameraRotationY: Float
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        context.coordinator.loadPLY(from: plyURL)
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updateCamera(
            distance: cameraDistance,
            rotationX: cameraRotationX,
            rotationY: cameraRotationY
        )
    }
    
    func makeCoordinator() -> SplatRenderer {
        SplatRenderer()
    }
}

class SplatRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?
    
    private var cameraDistance: Float = 3.0
    private var cameraRotationX: Float = 0.0
    private var cameraRotationY: Float = 0.0
    
    private var gaussians: [GaussianSplat] = []
    private var vertexBuffer: MTLBuffer?
    
    struct GaussianSplat {
        var position: SIMD3<Float>
        var color: SIMD4<Float>
        var scale: SIMD3<Float>
        var opacity: Float
    }
    
    override init() {
        super.init()
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        setupPipeline()
    }
    
    private func setupPipeline() {
        guard let device = device else { return }
        
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexIn {
            float3 position [[attribute(0)]];
            float4 color [[attribute(1)]];
            float scale [[attribute(2)]];
        };
        
        struct VertexOut {
            float4 position [[position]];
            float4 color;
            float pointSize [[point_size]];
        };
        
        struct Uniforms {
            float4x4 viewProjection;
            float2 screenSize;
        };
        
        vertex VertexOut vertex_main(
            VertexIn in [[stage_in]],
            constant Uniforms &uniforms [[buffer(1)]]
        ) {
            VertexOut out;
            out.position = uniforms.viewProjection * float4(in.position, 1.0);
            out.color = in.color;
            out.pointSize = max(1.0, in.scale * uniforms.screenSize.y / out.position.w * 0.5);
            return out;
        }
        
        fragment float4 fragment_main(
            VertexOut in [[stage_in]],
            float2 pointCoord [[point_coord]]
        ) {
            float dist = length(pointCoord - 0.5) * 2.0;
            float alpha = exp(-dist * dist * 4.0) * in.color.a;
            return float4(in.color.rgb, alpha);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "vertex_main")
            let fragmentFunc = library.makeFunction(name: "fragment_main")
            
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = fragmentFunc
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.depthAttachmentPixelFormat = .depth32Float
            
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float4
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.attributes[2].format = .float
            vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride
            vertexDescriptor.attributes[2].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride + MemoryLayout<Float>.stride + MemoryLayout<SIMD3<Float>>.stride
            
            descriptor.vertexDescriptor = vertexDescriptor
            
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to create pipeline: \(error)")
        }
    }
    
    func loadPLY(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self,
                  let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .ascii) else { return }
            
            var headerEnded = false
            var vertexCount = 0
            var parsedGaussians: [GaussianSplat] = []
            
            let lines = content.components(separatedBy: .newlines)
            var lineIndex = 0
            
            for line in lines {
                lineIndex += 1
                if line.starts(with: "element vertex") {
                    let parts = line.split(separator: " ")
                    if parts.count >= 3, let count = Int(parts[2]) {
                        vertexCount = count
                    }
                }
                if line == "end_header" {
                    headerEnded = true
                    break
                }
            }
            
            guard headerEnded else { return }
            
            for i in lineIndex..<min(lineIndex + vertexCount, lines.count) {
                let line = lines[i]
                let values = line.split(separator: " ").compactMap { Float($0) }
                
                if values.count >= 6 {
                    let position = SIMD3<Float>(values[0], values[1], values[2])
                    
                    var color = SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
                    if values.count >= 9 {
                        color = SIMD4<Float>(
                            values[6] / 255.0,
                            values[7] / 255.0,
                            values[8] / 255.0,
                            1.0
                        )
                    }
                    
                    let scale: Float = values.count >= 10 ? values[9] : 0.01
                    
                    parsedGaussians.append(GaussianSplat(
                        position: position,
                        color: color,
                        scale: SIMD3<Float>(repeating: scale),
                        opacity: 1.0
                    ))
                }
            }
            
            DispatchQueue.main.async {
                self.gaussians = parsedGaussians
                self.createVertexBuffer()
            }
        }
    }
    
    private func createVertexBuffer() {
        guard let device = device, !gaussians.isEmpty else { return }
        
        struct Vertex {
            var position: SIMD3<Float>
            var color: SIMD4<Float>
            var scale: Float
            var padding: SIMD3<Float> = .zero
        }
        
        let vertices = gaussians.map { splat in
            Vertex(
                position: splat.position,
                color: splat.color,
                scale: splat.scale.x
            )
        }
        
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
    }
    
    func updateCamera(distance: Float, rotationX: Float, rotationY: Float) {
        cameraDistance = distance
        cameraRotationX = rotationX
        cameraRotationY = rotationY
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let vertexBuffer = vertexBuffer else { return }
        
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let projection = perspectiveMatrix(fov: Float.pi / 3, aspect: aspect, near: 0.1, far: 100)
        let cameraView = viewMatrix(distance: cameraDistance, rotationX: cameraRotationX, rotationY: cameraRotationY)
        let viewProjection = projection * cameraView
        
        struct Uniforms {
            var viewProjection: simd_float4x4
            var screenSize: SIMD2<Float>
        }
        
        var uniforms = Uniforms(
            viewProjection: viewProjection,
            screenSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gaussians.count)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func drawableSize(_ view: MTKView) -> CGSize {
        view.drawableSize
    }
    
    private func perspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        ))
    }
    
    private func viewMatrix(distance: Float, rotationX: Float, rotationY: Float) -> simd_float4x4 {
        let translation = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, -distance, 1)
        ))
        
        let rotX = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(rotationX), sin(rotationX), 0),
            SIMD4<Float>(0, -sin(rotationX), cos(rotationX), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        
        let rotY = simd_float4x4(columns: (
            SIMD4<Float>(cos(rotationY), 0, -sin(rotationY), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sin(rotationY), 0, cos(rotationY), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        
        return translation * rotX * rotY
    }
}

#Preview {
    SplatViewerView(project: Project(
        id: UUID(),
        name: "Test Scene",
        inputImageURL: nil,
        outputPLYURL: URL(fileURLWithPath: "/tmp/test.ply"),
        createdAt: Date()
    ))
    .environmentObject(AppState())
    .frame(width: 800, height: 600)
}
