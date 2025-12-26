#!/bin/bash
set -e

SHARP_ENV_DIR="$HOME/.sharp-viewer"
SHARP_VENV="$SHARP_ENV_DIR/venv"

echo "Setting up SHARP environment..."

if [ ! -d "$SHARP_VENV" ]; then
    echo "Creating virtual environment..."
    mkdir -p "$SHARP_ENV_DIR"
    python3 -m venv "$SHARP_VENV"
fi

source "$SHARP_VENV/bin/activate"

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
