#!/bin/bash
set -e

SHARP_ENV_DIR="$HOME/.sharp-viewer"
MINICONDA_DIR="$SHARP_ENV_DIR/miniconda"
SHARP_VENV="$SHARP_ENV_DIR/venv"

echo "Setting up SHARP environment..."

# Add common paths
export PATH="/opt/homebrew/bin:/usr/local/bin:$MINICONDA_DIR/bin:$PATH"

# Find a suitable Python (3.10+)
find_python() {
    # Check our miniconda first
    if [ -x "$MINICONDA_DIR/bin/python3" ]; then
        echo "$MINICONDA_DIR/bin/python3"
        return
    fi
    
    # Try system pythons
    for py in "/opt/homebrew/bin/python3.13" "/opt/homebrew/bin/python3.12" "/opt/homebrew/bin/python3.11" "/usr/local/bin/python3.13" "/usr/local/bin/python3.12"; do
        if [ -x "$py" ]; then
            echo "$py"
            return
        fi
    done
    
    # Try PATH pythons
    for py in python3.13 python3.12 python3.11 python3.10; do
        if command -v $py &> /dev/null; then
            full_path=$(command -v $py)
            echo "$full_path"
            return
        fi
    done
    
    echo ""
}

PYTHON_BIN=$(find_python)

if [ -z "$PYTHON_BIN" ]; then
    echo "Python 3.10+ not found. Installing Miniconda..."
    
    mkdir -p "$SHARP_ENV_DIR"
    
    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
    else
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
    fi
    
    INSTALLER="$SHARP_ENV_DIR/miniconda_installer.sh"
    
    echo "Downloading Miniconda..."
    curl -fsSL "$MINICONDA_URL" -o "$INSTALLER"
    
    echo "Installing Miniconda (this may take a minute)..."
    bash "$INSTALLER" -b -p "$MINICONDA_DIR"
    rm "$INSTALLER"
    
    # Update PATH
    export PATH="$MINICONDA_DIR/bin:$PATH"
    
    PYTHON_BIN="$MINICONDA_DIR/bin/python3"
    
    if [ ! -x "$PYTHON_BIN" ]; then
        echo "ERROR: Miniconda installation failed"
        exit 1
    fi
fi

echo "Using Python: $PYTHON_BIN"
$PYTHON_BIN --version

mkdir -p "$SHARP_ENV_DIR"

if [ ! -d "$SHARP_VENV" ]; then
    echo "Creating virtual environment..."
    $PYTHON_BIN -m venv "$SHARP_VENV"
fi

source "$SHARP_VENV/bin/activate"

# Verify Python version in venv
VENV_VERSION=$(python3 -c 'import sys; print(sys.version_info.minor)')
echo "Virtual environment Python version: 3.$VENV_VERSION"

if [ "$VENV_VERSION" -lt 10 ]; then
    echo "Virtual environment has old Python. Recreating..."
    rm -rf "$SHARP_VENV"
    $PYTHON_BIN -m venv "$SHARP_VENV"
    source "$SHARP_VENV/bin/activate"
fi

if ! python3 -c "import sharp" 2>/dev/null; then
    echo "Installing ml-sharp (this may take a few minutes)..."
    pip install --upgrade pip
    
    cd "$SHARP_ENV_DIR"
    if [ ! -d "ml-sharp" ]; then
        echo "Cloning ml-sharp repository..."
        git clone https://github.com/apple/ml-sharp.git
    fi
    cd ml-sharp
    echo "Installing dependencies..."
    pip install -r requirements.txt
fi

echo "SHARP environment ready!"
echo "VENV_PATH=$SHARP_VENV"
