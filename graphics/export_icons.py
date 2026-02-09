#!/usr/bin/env python3
"""
Export icons.svg to PNG at multiple DPIs using Inkscape.
Generates icons-16.png, icons-32.png, and icons-64.png from icons.svg.
"""

import subprocess
import sys
from pathlib import Path

def find_inkscape():
    """Find Inkscape executable on the system."""
    # Common installation paths on Windows
    possible_paths = [
        r"C:\Program Files\Inkscape\bin\inkscape.exe",
        r"C:\Program Files (x86)\Inkscape\bin\inkscape.exe",
        Path.home() / "AppData" / "Local" / "Programs" / "Inkscape" / "bin" / "inkscape.exe",
    ]
    
    for path in possible_paths:
        if Path(path).exists():
            return str(path)
    
    # Try just "inkscape" if it's in PATH
    try:
        result = subprocess.run(["inkscape", "--version"], 
                              capture_output=True, 
                              text=True, 
                              timeout=5)
        if result.returncode == 0:
            return "inkscape"
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    
    return None

def export_svg_to_png(inkscape_path, svg_file, output_file, dpi):
    """Export SVG to PNG at specified DPI using Inkscape."""
    cmd = [
        inkscape_path,
        "--export-type=png",
        "--export-area-page",
        f"--export-dpi={dpi}",
        f"--export-filename={output_file}",
        str(svg_file)
    ]
    
    print(f"Exporting {output_file} at {dpi} DPI...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error exporting {output_file}:")
        print(result.stderr)
        return False
    
    print(f"  ✓ Created {output_file}")
    return True

def main():
    # Find script directory
    script_dir = Path(__file__).parent
    icons_dir = script_dir / "icons"
    svg_file = icons_dir / "icons.svg"
    
    # Check if icons.svg exists
    if not svg_file.exists():
        print(f"Error: {svg_file} not found!")
        sys.exit(1)
    
    # Find Inkscape
    inkscape_path = find_inkscape()
    if not inkscape_path:
        print("Error: Inkscape not found!")
        print("Please install Inkscape or add it to your PATH")
        sys.exit(1)
    
    print(f"Using Inkscape: {inkscape_path}")
    print(f"Source: {svg_file}\n")
    
    # Export configurations: (DPI, output filename)
    exports = [
        (24, "icons-16.png"),
        (48, "icons-32.png"),
        (96, "icons-64.png"),
    ]
    
    success_count = 0
    for dpi, filename in exports:
        output_file = icons_dir / filename
        if export_svg_to_png(inkscape_path, svg_file, output_file, dpi):
            success_count += 1
    
    print(f"\nCompleted: {success_count}/{len(exports)} exports successful")
    
    if success_count < len(exports):
        sys.exit(1)

if __name__ == "__main__":
    main()
