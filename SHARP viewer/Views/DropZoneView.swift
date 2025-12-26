import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragOver = false
    @State private var showFilePicker = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            isDragOver ? Color.accentColor : Color.primary.opacity(0.2),
                            style: StrokeStyle(lineWidth: 2, dash: [12, 8])
                        )
                }
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(isDragOver ? Color.accentColor : .primary)
                        .symbolEffect(.pulse, options: .repeating, isActive: isDragOver)
                }
                
                VStack(spacing: 8) {
                    Text("Drop an image to create a 3D scene")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("SHARP will generate a 3D Gaussian splat in seconds")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose Image", systemImage: "folder")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            }
            .padding(60)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.image], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                processImage(url: url)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        provider.loadObject(ofClass: URL.self) { item, _ in
            if let url = item {
                DispatchQueue.main.async {
                    processImage(url: url)
                }
            }
        }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    processImage(url: url)
                }
            }
        }
    }
    
    private func processImage(url: URL) {
        Task {
            await SHARPService.shared.generateSplat(from: url, appState: appState)
        }
    }
}

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
