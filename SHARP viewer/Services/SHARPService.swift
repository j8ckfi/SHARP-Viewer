import Foundation

@MainActor
class SHARPService: ObservableObject {
    static let shared = SHARPService()
    
    private var currentProcess: Process?
    private let sharpEnvDir: URL
    private let scriptsDir: URL
    
    init() {
        sharpEnvDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sharp-viewer", isDirectory: true)
        
        if let bundlePath = Bundle.main.resourceURL {
            scriptsDir = bundlePath.appendingPathComponent("Scripts", isDirectory: true)
        } else {
            scriptsDir = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts", isDirectory: true)
        }
    }
    
    var isEnvironmentReady: Bool {
        let venvPython = sharpEnvDir
            .appendingPathComponent("venv/bin/python3")
        return FileManager.default.fileExists(atPath: venvPython.path)
    }
    
    func setupEnvironment(progress: @escaping (String) -> Void) async throws {
        progress("Setting up SHARP environment...")
        
        let setupScript = scriptsDir.appendingPathComponent("setup_sharp.sh")
        
        guard FileManager.default.fileExists(atPath: setupScript.path) else {
            throw SHARPError.setupScriptMissing
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [setupScript.path]
        process.currentDirectoryURL = sharpEnvDir
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        try process.run()
        
        let outputHandle = outputPipe.fileHandleForReading
        
        for try await line in outputHandle.bytes.lines {
            progress(line)
        }
        
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SHARPError.setupFailed
        }
    }
    
    func generateSplat(from imageURL: URL, appState: AppState) async {
        appState.isGenerating = true
        appState.generationProgress = "Preparing..."
        
        defer {
            appState.isGenerating = false
        }
        
        do {
            if !isEnvironmentReady {
                try await setupEnvironment { [weak appState] message in
                    DispatchQueue.main.async {
                        appState?.generationProgress = message
                    }
                }
            }
            
            let projectName = imageURL.deletingPathExtension().lastPathComponent
                + "-" + UUID().uuidString.prefix(6)
            let projectDir = appState.projectDirectory(for: projectName)
            
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            
            let destImage = projectDir.appendingPathComponent(imageURL.lastPathComponent)
            try FileManager.default.copyItem(at: imageURL, to: destImage)
            
            appState.generationProgress = "Loading SHARP model..."
            
            let venvPython = sharpEnvDir.appendingPathComponent("venv/bin/python3")
            let generateScript = scriptsDir.appendingPathComponent("generate_splat.py")
            
            let process = Process()
            process.executableURL = venvPython
            process.arguments = [generateScript.path, destImage.path, projectDir.path]
            process.currentDirectoryURL = sharpEnvDir.appendingPathComponent("ml-sharp")
            
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = sharpEnvDir.appendingPathComponent("venv/bin").path + ":" + (environment["PATH"] ?? "")
            process.environment = environment
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            currentProcess = process
            try process.run()
            
            let outputHandle = outputPipe.fileHandleForReading
            
            for try await line in outputHandle.bytes.lines {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if let message = json["message"] as? String {
                        appState.generationProgress = message
                    }
                    
                    if let error = json["error"] as? String {
                        throw SHARPError.generationFailed(error)
                    }
                    
                    if json["status"] as? String == "complete",
                       let outputPath = json["output_path"] as? String {
                        
                        appState.loadRecentProjects()
                        
                        if let project = appState.recentProjects.first(where: { $0.outputPLYURL.path == outputPath }) {
                            appState.currentProject = project
                        }
                    }
                }
            }
            
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw SHARPError.generationFailed("Process exited with code \(process.terminationStatus)")
            }
            
        } catch {
            appState.generationProgress = "Error: \(error.localizedDescription)"
            try? await Task.sleep(for: .seconds(3))
        }
    }
    
    func cancelGeneration() {
        currentProcess?.terminate()
        currentProcess = nil
    }
}

enum SHARPError: LocalizedError {
    case setupScriptMissing
    case setupFailed
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .setupScriptMissing:
            return "Setup script not found in app bundle"
        case .setupFailed:
            return "Failed to set up SHARP environment"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}
