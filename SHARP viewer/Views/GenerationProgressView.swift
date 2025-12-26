import SwiftUI

struct GenerationProgressView: View {
    @EnvironmentObject var appState: AppState
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: CGFloat(80 + index * 30), height: CGFloat(80 + index * 30))
                        .rotationEffect(.degrees(rotationAngle + Double(index * 60)))
                }
                
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.primary)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            }
            
            VStack(spacing: 12) {
                Text("Generating 3D Scene")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(appState.generationProgress.isEmpty ? "Loading SHARP model..." : appState.generationProgress)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            
            GlassEffectContainer {
                Button(role: .cancel) {
                    SHARPService.shared.cancelGeneration()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    GenerationProgressView()
        .environmentObject({
            let state = AppState()
            state.isGenerating = true
            state.generationProgress = "Processing image..."
            return state
        }())
        .frame(width: 600, height: 500)
}
