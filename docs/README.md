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
