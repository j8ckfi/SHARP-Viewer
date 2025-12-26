#!/bin/bash
set -e

SHARP_ENV_DIR="$HOME/.sharp-viewer"
SHARP_VENV="$SHARP_ENV_DIR/venv"

echo "Setting up SHARP environment..."

# Find a suitable Python (3.10+)
find_python() {
    # Try homebrew Python 3.13 first
    if [ -x "/opt/homebrew/bin/python3.13" ]; then
        echo "/opt/homebrew/bin/python3.13"
        return
    fi
    # Try python3.13
    if command -v python3.13 &> /dev/null; then
        echo "python3.13"
        return
    fi
    # Try python3.12
    if command -v python3.12 &> /dev/null; then
        echo "python3.12"
        return
    fi
    # Try homebrew python3
    if [ -x "/opt/homebrew/bin/python3" ]; then
        version=$(/opt/homebrew/bin/python3 -c 'import sys; print(sys.version_info.minor)')
        if [ "$version" -ge 10 ]; then
            echo "/opt/homebrew/bin/python3"
            return
        fi
    fi
    echo ""
}

PYTHON_BIN=$(find_python)

if [ -z "$PYTHON_BIN" ]; then
    echo "Python 3.10+ not found. Installing via Homebrew..."
    
    if ! command -v brew &> /dev/null; then
        echo "ERROR: Homebrew not found. Please install Homebrew first:"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    
    brew install python@3.13
    PYTHON_BIN="/opt/homebrew/bin/python3.13"
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
if [ "$VENV_VERSION" -lt 10 ]; then
    echo "Virtual environment has Python 3.$VENV_VERSION, need 3.10+. Recreating..."
    rm -rf "$SHARP_VENV"
    $PYTHON_BIN -m venv "$SHARP_VENV"
    source "$SHARP_VENV/bin/activate"
fi

if ! python3 -c "import sharp" 2>/dev/null; then
    echo "Installing ml-sharp..."
    pip install --upgrade pip
    
    cd "$SHARP_ENV_DIR"
    if [ ! -d "ml-sharp" ]; then
        git clone https://github.com/apple/ml-sharp.git
    fi
    cd ml-sharp
    pip install -r requirements.txt
fi

echo "SHARP environment ready!"
echo "VENV_PATH=$SHARP_VENV"
