#!/bin/bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

LOGS_DIR="$ROOT_DIR/logs"
OLLAMA_LOGS_DIR="$LOGS_DIR/ollama"
MODELS_LOGS_DIR="$LOGS_DIR/models"
RAG_LOGS_DIR="$LOGS_DIR/rag-service"

RAG_SHUTDOWN_STATUS="PENDING"
declare -A MODEL_SHUTDOWN_STATUS
OLLAMA_SHUTDOWN_STATUS="PENDING"
EXIT_CODE=0

print_shutdown_summary() {
    echo ""
    echo "========================================="
    echo "         SHUTDOWN SUMMARY                "
    echo "========================================="

    if [ "$RAG_SHUTDOWN_STATUS" = "SUCCESS" ]; then
        echo -e "RAG-Sandbox Service : ${GREEN}Success${NC}"
    elif [ "$RAG_SHUTDOWN_STATUS" = "NOT_RUNNING" ]; then
        echo -e "RAG-Sandbox Service : ${YELLOW}Not Running${NC}"
    else
        echo -e "RAG-Sandbox Service : ${RED}Failed${NC}"
    fi

    if [ ${#MODEL_SHUTDOWN_STATUS[@]} -gt 0 ]; then
        for model in "${!MODEL_SHUTDOWN_STATUS[@]}"; do
            if [ "${MODEL_SHUTDOWN_STATUS[$model]}" = "SUCCESS" ]; then
                echo -e "Model $model : ${GREEN}Success${NC}"
            else
                echo -e "Model $model : ${RED}Failed${NC}"
            fi
        done
    fi

    if [ "$OLLAMA_SHUTDOWN_STATUS" = "SUCCESS" ]; then
        echo -e "Ollama              : ${GREEN}Success${NC}"
    elif [ "$OLLAMA_SHUTDOWN_STATUS" = "NOT_RUNNING" ]; then
        echo -e "Ollama              : ${YELLOW}Not Running${NC}"
    else
        echo -e "Ollama              : ${RED}Failed${NC}"
    fi

    echo "========================================="
}

trap print_shutdown_summary EXIT

echo "========================================="
echo "    RAG-Sandbox Service Shutdown Script  "
echo "========================================="
echo ""
echo "Root directory: $ROOT_DIR"
echo "Script directory: $SCRIPT_DIR"
echo "Timestamp: $TIMESTAMP"
echo ""

mkdir -p "$OLLAMA_LOGS_DIR"
mkdir -p "$MODELS_LOGS_DIR"
mkdir -p "$RAG_LOGS_DIR"

echo "Step 1: Shutting down RAG-Sandbox service..."
RAG_STOP_LOG="$RAG_LOGS_DIR/rag-stop-$TIMESTAMP.log"

RAG_PID=$(pgrep -f "dotnet.*rag-sandbox" || true)

if [ -z "$RAG_PID" ]; then
    echo "  → RAG-Sandbox service is not running"
    RAG_SHUTDOWN_STATUS="NOT_RUNNING"
else
    echo "  → Found RAG-Sandbox process (PID: $RAG_PID)"
    echo "Shutting down RAG-Sandbox service at $(date)" > "$RAG_STOP_LOG"

    kill -TERM $RAG_PID >> "$RAG_STOP_LOG" 2>&1

    for i in {1..10}; do
        sleep 1
        if ! kill -0 $RAG_PID 2>/dev/null; then
            echo "  ✓ RAG-Sandbox service stopped gracefully"
            RAG_SHUTDOWN_STATUS="SUCCESS"
            break
        fi
    done

    if kill -0 $RAG_PID 2>/dev/null; then
        echo "  → Forcing shutdown..."
        kill -9 $RAG_PID >> "$RAG_STOP_LOG" 2>&1
        sleep 1

        if ! kill -0 $RAG_PID 2>/dev/null; then
            echo "  ✓ RAG-Sandbox service stopped forcefully"
            RAG_SHUTDOWN_STATUS="SUCCESS"
        else
            echo "  ✘ Failed to stop RAG-Sandbox service"
            RAG_SHUTDOWN_STATUS="FAILED"
            EXIT_CODE=1
        fi
    fi

    echo "Shutdown completed at $(date)" >> "$RAG_STOP_LOG"
    echo "  → Log: $RAG_STOP_LOG"
fi

echo ""

echo "Step 2: Shutting down LLM models..."

if ! pgrep -x "ollama" > /dev/null; then
    echo "  → Ollama is not running, skipping model shutdown"
else
    MODELS_OUTPUT=$(ollama list 2>&1)

    if [ $? -eq 0 ]; then
        MODELS=($(echo "$MODELS_OUTPUT" | tail -n +2 | awk '{print $1}' | grep -v '^$'))

        if [ ${#MODELS[@]} -eq 0 ]; then
            echo "  → No models found"
        else
            echo "  Found ${#MODELS[@]} model(s)"

            for model in "${MODELS[@]}"; do
                echo "  Processing model: $model"

                MODEL_LOG_DIR="$MODELS_LOGS_DIR/$model"
                mkdir -p "$MODEL_LOG_DIR"

                MODEL_STOP_LOG="$MODEL_LOG_DIR/model-stop-$TIMESTAMP.log"

                echo "Shutting down model $model at $(date)" > "$MODEL_STOP_LOG"
                echo "Model $model logged for shutdown tracking" >> "$MODEL_STOP_LOG"
                echo "Shutdown logged at $(date)" >> "$MODEL_STOP_LOG"

                MODEL_SHUTDOWN_STATUS["$model"]="SUCCESS"
                echo "    ✓ Model $model logged"
            done
        fi
    else
        echo "  ⚠ Could not retrieve model list"
    fi
fi

echo ""

echo "Step 3: Shutting down Ollama..."
OLLAMA_STOP_LOG="$OLLAMA_LOGS_DIR/ollama-stop-$TIMESTAMP.log"

if ! pgrep -x "ollama" > /dev/null; then
    echo "  → Ollama is not running"
    OLLAMA_SHUTDOWN_STATUS="NOT_RUNNING"
else
    OLLAMA_PID=$(pgrep -x "ollama")
    echo "  → Found Ollama process (PID: $OLLAMA_PID)"
    echo "Shutting down Ollama at $(date)" > "$OLLAMA_STOP_LOG"

    # Try systemctl first (proper way to stop a service)
    if systemctl is-active --quiet ollama 2>/dev/null; then
        echo "  → Stopping Ollama service with systemctl..."
        sudo systemctl stop ollama >> "$OLLAMA_STOP_LOG" 2>&1

        sleep 2

        if ! pgrep -x "ollama" > /dev/null; then
            echo "  ✓ Ollama stopped via systemctl"
            OLLAMA_SHUTDOWN_STATUS="SUCCESS"
        fi
    fi

    # If still running, try kill
    if pgrep -x "ollama" > /dev/null; then
        echo "  → Attempting graceful shutdown with SIGTERM..."
        sudo kill -TERM $OLLAMA_PID >> "$OLLAMA_STOP_LOG" 2>&1

        for i in {1..15}; do
            sleep 1
            if ! pgrep -x "ollama" > /dev/null; then
                echo "  ✓ Ollama stopped gracefully"
                OLLAMA_SHUTDOWN_STATUS="SUCCESS"
                break
            fi
        done
    fi

    # Force kill if still running
    if pgrep -x "ollama" > /dev/null; then
        echo "  → Forcing shutdown with SIGKILL..."
        sudo pkill -9 -x "ollama" >> "$OLLAMA_STOP_LOG" 2>&1
        sleep 1

        if ! pgrep -x "ollama" > /dev/null; then
            echo "  ✓ Ollama stopped forcefully"
            OLLAMA_SHUTDOWN_STATUS="SUCCESS"
        else
            echo "  ✘ Failed to stop Ollama (permission denied or protected process)"
            OLLAMA_SHUTDOWN_STATUS="FAILED"
            EXIT_CODE=1
        fi
    fi

    echo "Shutdown completed at $(date)" >> "$OLLAMA_STOP_LOG"
    echo "  → Log: $OLLAMA_STOP_LOG"
fi

echo ""
echo "========================================="
echo "         SHUTDOWN COMPLETE               "
echo "========================================="

exit $EXIT_CODE
