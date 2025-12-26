import SwiftUI

@main
struct SHARP_viewerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var currentProject: Project?
    @Published var recentProjects: [Project] = []
    @Published var isGenerating = false
    @Published var generationProgress: String = ""
    @Published var setupComplete = false
    
    private let projectsDirectory: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        projectsDirectory = docs.appendingPathComponent("SHARP Viewer", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        loadRecentProjects()
    }
    
    func loadRecentProjects() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        recentProjects = contents
            .filter { $0.hasDirectoryPath }
            .compactMap { url -> Project? in
                let plyFiles = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "ply" } ?? []
                guard let ply = plyFiles.first else { return nil }
                
                let imageFiles = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) } ?? []
                
                return Project(
                    id: UUID(),
                    name: url.lastPathComponent,
                    inputImageURL: imageFiles.first,
                    outputPLYURL: ply,
                    createdAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    func projectDirectory(for name: String) -> URL {
        projectsDirectory.appendingPathComponent(name, isDirectory: true)
    }
}

struct Project: Identifiable {
    let id: UUID
    let name: String
    let inputImageURL: URL?
    let outputPLYURL: URL
    let createdAt: Date
}
