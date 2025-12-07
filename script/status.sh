#!/bin/bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RAG_STATUS="UNKNOWN"
OLLAMA_STATUS="UNKNOWN"
declare -A MODEL_STATUS

echo "========================================="
echo "         SYSTEM STATUS CHECK             "
echo "========================================="
echo ""
echo "Root directory: $ROOT_DIR"
echo ""

echo "Checking RAG-Sandbox service..."
RAG_PID=$(pgrep -f "dotnet.*rag-sandbox" || true)

if [ -n "$RAG_PID" ]; then
    RAG_STATUS="RUNNING"
    echo "  → Found process (PID: $RAG_PID)"
else
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/api/chat/models" 2>/dev/null | grep -q "200"; then
        RAG_STATUS="RUNNING"
        echo "  → Service responding on port 5000"
    else
        RAG_STATUS="NOT RUNNING"
        echo "  → Not detected"
    fi
fi

echo "Checking Ollama..."
if ! command -v ollama &> /dev/null; then
    OLLAMA_STATUS="NOT INSTALLED"
    echo "  → ollama command not found"
else
    if pgrep -x "ollama" > /dev/null; then
        OLLAMA_STATUS="RUNNING"
        echo "  → Process running"
    else
        OLLAMA_STATUS="NOT RUNNING"
        echo "  → Process not running"
    fi
fi

echo "Checking LLM models..."
if [ "$OLLAMA_STATUS" = "RUNNING" ]; then
    MODELS_OUTPUT=$(ollama list 2>&1)

    if [ $? -eq 0 ]; then
        MODELS=($(echo "$MODELS_OUTPUT" | tail -n +2 | awk '{print $1}' | grep -v '^$'))

        if [ ${#MODELS[@]} -eq 0 ]; then
            echo "  → No models installed"
        else
            echo "  → Found ${#MODELS[@]} model(s)"

            # Get list of currently loaded models
            LOADED_MODELS=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$')

            for model in "${MODELS[@]}"; do
                # Check if model is loaded in memory
                if echo "$LOADED_MODELS" | grep -q "^${model}$"; then
                    MODEL_STATUS["$model"]="LOADED"
                    echo "    ● $model (loaded in memory)"
                else
                    # Check if model is available
                    ollama show "$model" &> /dev/null
                    if [ $? -eq 0 ]; then
                        MODEL_STATUS["$model"]="AVAILABLE"
                        echo "    ○ $model (available)"
                    else
                        MODEL_STATUS["$model"]="ERROR"
                        echo "    ✘ $model (error)"
                    fi
                fi
            done
        fi
    else
        echo "  → Could not retrieve model list"
    fi
else
    echo "  → Skipped (Ollama not running)"
fi

echo ""
echo "========================================="
echo "         SYSTEM STATUS                   "
echo "========================================="

if [ "$RAG_STATUS" = "RUNNING" ]; then
    echo -e "RAG-Sandbox Service : ${GREEN}RUNNING${NC}"
elif [ "$RAG_STATUS" = "NOT RUNNING" ]; then
    echo -e "RAG-Sandbox Service : ${YELLOW}NOT RUNNING${NC}"
else
    echo -e "RAG-Sandbox Service : ${BLUE}UNKNOWN${NC}"
fi

if [ "$OLLAMA_STATUS" = "RUNNING" ]; then
    echo -e "Ollama              : ${GREEN}RUNNING${NC}"
elif [ "$OLLAMA_STATUS" = "NOT RUNNING" ]; then
    echo -e "Ollama              : ${YELLOW}NOT RUNNING${NC}"
elif [ "$OLLAMA_STATUS" = "NOT INSTALLED" ]; then
    echo -e "Ollama              : ${RED}NOT INSTALLED${NC}"
else
    echo -e "Ollama              : ${BLUE}UNKNOWN${NC}"
fi

if [ ${#MODEL_STATUS[@]} -gt 0 ]; then
    for model in "${!MODEL_STATUS[@]}"; do
        if [ "${MODEL_STATUS[$model]}" = "LOADED" ]; then
            echo -e "$model : ${GREEN}LOADED${NC}"
        elif [ "${MODEL_STATUS[$model]}" = "AVAILABLE" ]; then
            echo -e "$model : ${YELLOW}AVAILABLE${NC}"
        else
            echo -e "$model : ${RED}ERROR${NC}"
        fi
    done
fi

echo "========================================="

exit 0
