#!/usr/bin/env python3
"""
Generate 3D Gaussian splats from images using SHARP.
Called by the Swift app via Process.
"""

import sys
import os
import json
import subprocess
from pathlib import Path

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: generate_splat.py <input_image> <output_dir>"}))
        sys.exit(1)
    
    input_image = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    
    if not input_image.exists():
        print(json.dumps({"error": f"Input image not found: {input_image}"}))
        sys.exit(1)
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(json.dumps({"status": "starting", "message": "Loading SHARP model..."}))
    sys.stdout.flush()
    
    result = subprocess.run(
        ["sharp", "predict", "-i", str(input_image), "-o", str(output_dir)],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(json.dumps({"error": f"SHARP failed: {result.stderr}"}))
        sys.exit(1)
    
    ply_files = list(output_dir.glob("*.ply"))
    if not ply_files:
        print(json.dumps({"error": "No .ply file generated"}))
        sys.exit(1)
    
    output_ply = ply_files[0]
    print(json.dumps({
        "status": "complete",
        "output_path": str(output_ply),
        "message": "3D splat generated successfully!"
    }))

if __name__ == "__main__":
    main()
