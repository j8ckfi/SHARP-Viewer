import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            if appState.isGenerating {
                GenerationProgressView()
            } else if let project = appState.currentProject {
                SplatViewerView(project: project)
            } else {
                DropZoneView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.currentProject != nil {
                    Button("New", systemImage: "plus") {
                        appState.currentProject = nil
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        List(selection: Binding(
            get: { appState.currentProject?.id },
            set: { id in
                appState.currentProject = appState.recentProjects.first { $0.id == id }
            }
        )) {
            Section("Recent") {
                ForEach(appState.recentProjects) { project in
                    ProjectRowView(project: project)
                        .tag(project.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SHARP")
    }
}

struct ProjectRowView: View {
    let project: Project
    
    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = project.inputImageURL,
               let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(project.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
