import Foundation
import Combine

@MainActor
class SHARPService: ObservableObject {
    static let shared = SHARPService()
    
    private var currentProcess: Process?
    private let sharpEnvDir: URL
    private let scriptsDir: URL
    
    init() {
        sharpEnvDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sharp-viewer", isDirectory: true)
        
        // Scripts are copied to Resources directly (not in a Scripts subfolder)
        if let bundlePath = Bundle.main.resourceURL {
            scriptsDir = bundlePath
        } else {
            // Fallback for development - look in the source Scripts folder
            scriptsDir = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts", isDirectory: true)
        }
        
        print("[SHARPService] Scripts directory: \(scriptsDir.path)")
    }
    
    var isEnvironmentReady: Bool {
        let venvPython = sharpEnvDir
            .appendingPathComponent("venv/bin/python3")
        return FileManager.default.fileExists(atPath: venvPython.path)
    }
    
    func setupEnvironment(progress: @escaping (String) -> Void) async throws {
        progress("Setting up SHARP environment...")
        
        let setupScript = scriptsDir.appendingPathComponent("setup_sharp.sh")
        
        print("[SHARPService] Looking for setup script at: \(setupScript.path)")
        
        guard FileManager.default.fileExists(atPath: setupScript.path) else {
            print("[SHARPService] ERROR: Setup script not found!")
            throw SHARPError.setupScriptMissing
        }
        
        // Create the environment directory if it doesn't exist
        try FileManager.default.createDirectory(at: sharpEnvDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [setupScript.path]
        process.currentDirectoryURL = sharpEnvDir
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        print("[SHARPService] Running setup script...")
        try process.run()
        
        let outputHandle = outputPipe.fileHandleForReading
        
        for try await line in outputHandle.bytes.lines {
            print("[SHARPService] Setup: \(line)")
            progress(line)
        }
        
        process.waitUntilExit()
        
        print("[SHARPService] Setup exited with code: \(process.terminationStatus)")
        
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
            print("[SHARPService] Starting generation from: \(imageURL.path)")
            
            if !isEnvironmentReady {
                print("[SHARPService] Environment not ready, setting up...")
                try await setupEnvironment { [weak appState] message in
                    DispatchQueue.main.async {
                        appState?.generationProgress = message
                    }
                }
            }
            
            print("[SHARPService] Environment ready, checking paths...")
            
            let projectName = imageURL.deletingPathExtension().lastPathComponent
                + "-" + UUID().uuidString.prefix(6)
            let projectDir = appState.projectDirectory(for: projectName)
            
            print("[SHARPService] Project dir: \(projectDir.path)")
            
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            
            // Need to access security-scoped resource for dropped files
            let accessing = imageURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    imageURL.stopAccessingSecurityScopedResource()
                }
            }
            
            let destImage = projectDir.appendingPathComponent(imageURL.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: destImage.path) {
                try FileManager.default.removeItem(at: destImage)
            }
            try FileManager.default.copyItem(at: imageURL, to: destImage)
            
            print("[SHARPService] Copied image to: \(destImage.path)")
            
            appState.generationProgress = "Loading SHARP model..."
            
            let venvPython = sharpEnvDir.appendingPathComponent("venv/bin/python3")
            let generateScript = scriptsDir.appendingPathComponent("generate_splat.py")
            
            print("[SHARPService] Python: \(venvPython.path)")
            print("[SHARPService] Script: \(generateScript.path)")
            
            guard FileManager.default.fileExists(atPath: venvPython.path) else {
                throw SHARPError.generationFailed("Python not found at \(venvPython.path)")
            }
            
            guard FileManager.default.fileExists(atPath: generateScript.path) else {
                throw SHARPError.generationFailed("Generate script not found at \(generateScript.path)")
            }
            
            let mlSharpDir = sharpEnvDir.appendingPathComponent("ml-sharp")
            guard FileManager.default.fileExists(atPath: mlSharpDir.path) else {
                throw SHARPError.generationFailed("ml-sharp not found at \(mlSharpDir.path)")
            }
            
            let process = Process()
            process.executableURL = venvPython
            process.arguments = [generateScript.path, destImage.path, projectDir.path]
            process.currentDirectoryURL = mlSharpDir
            
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = sharpEnvDir.appendingPathComponent("venv/bin").path + ":" + (environment["PATH"] ?? "")
            process.environment = environment
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            currentProcess = process
            
            print("[SHARPService] Running generation process...")
            try process.run()
            
            let outputHandle = outputPipe.fileHandleForReading
            
            for try await line in outputHandle.bytes.lines {
                print("[SHARPService] Output: \(line)")
                
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
                        
                        print("[SHARPService] Complete! Output: \(outputPath)")
                        
                        appState.loadRecentProjects()
                        
                        if let project = appState.recentProjects.first(where: { $0.outputPLYURL.path == outputPath }) {
                            appState.currentProject = project
                        }
                    }
                }
            }
            
            process.waitUntilExit()
            
            print("[SHARPService] Process exited with code: \(process.terminationStatus)")
            
            if process.terminationStatus != 0 {
                throw SHARPError.generationFailed("Process exited with code \(process.terminationStatus)")
            }
            
        } catch {
            print("[SHARPService] ERROR: \(error)")
            appState.generationProgress = "Error: \(error.localizedDescription)"
            try? await Task.sleep(for: .seconds(5))
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
