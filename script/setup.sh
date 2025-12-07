#!/bin/bash

# Detect the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The parent directory (one level above the script directory)
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Define paths
REPO_URL="https://github.com/krunchyMonkey/RAG-Sandbox"
REPO_NAME="RAG-Sandbox"
REPO_PATH="$PARENT_DIR/$REPO_NAME"
DOCS_PATH="$PARENT_DIR/docs"
README_PATH="$DOCS_PATH/README.md"

echo "========================================="
echo "RAG-Sandbox Setup Script"
echo "========================================="
echo ""
echo "Script location: $SCRIPT_DIR"
echo "Parent directory: $PARENT_DIR"
echo ""

# Clone the repository
echo "Step 1: Cloning repository..."
if [ -d "$REPO_PATH" ]; then
    echo "  → Repository already exists at: $REPO_PATH"
    echo "  → Skipping clone."
else
    echo "  → Cloning $REPO_URL to $REPO_PATH"
    git clone "$REPO_URL" "$REPO_PATH"
    if [ $? -eq 0 ]; then
        echo "  → Clone successful!"
    else
        echo "  → ERROR: Clone failed!"
        exit 1
    fi
fi
echo ""

# Create docs folder
echo "Step 2: Creating docs folder..."
if [ -d "$DOCS_PATH" ]; then
    echo "  → Docs folder already exists at: $DOCS_PATH"
else
    mkdir -p "$DOCS_PATH"
    echo "  → Created docs folder at: $DOCS_PATH"
fi
echo ""

# Create README.md
echo "Step 3: Creating README.md..."
cat > "$README_PATH" << 'EOF'
# RAG-Sandbox Setup

## What This Script Does

This setup script automates the initialization of the RAG-Sandbox development environment. When executed, it:

1. Detects its own location on the filesystem
2. Clones the RAG-Sandbox repository from GitHub
3. Creates a documentation folder structure
4. Generates this README file

The script is designed to work regardless of where it is executed from, using its physical file location to determine all paths.

## Folder Structure

The script creates the following directory structure:

```
root/
├── RAG-Sandbox/   ← The cloned GitHub repository
├── docs/          ← Documentation folder with this README
└── script/        ← Contains the setup script itself
```

### Directory Descriptions

- **RAG-Sandbox/**: The main repository cloned from https://github.com/krunchyMonkey/RAG-Sandbox
- **docs/**: Documentation and reference materials for the project
- **script/**: Contains automation scripts for setup and maintenance

## Usage

Simply run the setup script from any location:

```bash
./script/setup.sh
```

The script will automatically determine the correct paths and set up the environment.
EOF

echo "  → README.md created at: $README_PATH"
echo ""

echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Folder structure created at: $PARENT_DIR"
echo "  - Repository: $REPO_PATH"
echo "  - Documentation: $DOCS_PATH"
echo ""
