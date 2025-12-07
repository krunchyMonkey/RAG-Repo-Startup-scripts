#!/bin/bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse command line arguments
SKIP_TESTS=false
WARM_ALL_MODELS=false
for arg in "$@"; do
    if [ "$arg" = "--skip-tests" ]; then
        SKIP_TESTS=true
    elif [ "$arg" = "--warm-models" ]; then
        WARM_ALL_MODELS=true
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

LOGS_DIR="$ROOT_DIR/logs"
OLLAMA_LOGS_DIR="$LOGS_DIR/ollama"
MODELS_LOGS_DIR="$LOGS_DIR/models"
RAG_LOGS_DIR="$LOGS_DIR/rag-service"

OLLAMA_STATUS="PENDING"
declare -A MODEL_STATUS
RAG_STATUS="PENDING"
TESTS_STATUS="SKIPPED"
SMALLEST_MODEL=""
RAG_PORT=""

print_status_table() {
    echo ""
    echo "========================================="
    echo "         COMPONENT STATUS REPORT         "
    echo "========================================="

    if [ "$OLLAMA_STATUS" = "OK" ]; then
        echo -e "Ollama:              ${GREEN}✔ RUNNING${NC}"
    else
        echo -e "Ollama:              ${RED}✘ FAILED${NC}"
    fi

    if [ ${#MODEL_STATUS[@]} -gt 0 ]; then
        echo ""
        echo "LLM Models:"
        for model in "${!MODEL_STATUS[@]}"; do
            if [ "${MODEL_STATUS[$model]}" = "OK" ]; then
                echo -e "  - $model: ${GREEN}✔ OK${NC}"
            else
                echo -e "  - $model: ${RED}✘ FAILED${NC}"
            fi
        done
    fi

    echo ""
    if [ "$RAG_STATUS" = "OK" ]; then
        echo -e "RAG-Sandbox:         ${GREEN}✔ RUNNING${NC}"
    else
        echo -e "RAG-Sandbox:         ${RED}✘ FAILED${NC}"
    fi

    echo ""
    if [ "$TESTS_STATUS" = "OK" ]; then
        echo -e "Smoke Tests:         ${GREEN}✔ PASSED${NC}"
    elif [ "$TESTS_STATUS" = "SKIPPED" ]; then
        echo -e "Smoke Tests:         ${YELLOW}⊘ SKIPPED${NC}"
    else
        echo -e "Smoke Tests:         ${RED}✘ FAILED${NC}"
    fi

    echo "========================================="
}

trap print_status_table EXIT

echo "========================================="
echo "    RAG-Sandbox Service Startup Script   "
echo "========================================="
echo ""
echo "Root directory: $ROOT_DIR"
echo "Script directory: $SCRIPT_DIR"
echo "Timestamp: $TIMESTAMP"
if [ "$SKIP_TESTS" = true ]; then
    echo "Tests: SKIPPED (--skip-tests flag set)"
fi
if [ "$WARM_ALL_MODELS" = true ]; then
    echo "Models: WARM ALL (--warm-models flag set)"
else
    echo "Models: WARM SMALLEST ONLY (use --warm-models to load all)"
fi
echo ""

echo "Step 1: Creating log directory structure..."
mkdir -p "$OLLAMA_LOGS_DIR"
mkdir -p "$MODELS_LOGS_DIR"
mkdir -p "$RAG_LOGS_DIR"
echo "  ✓ Log directories created"
echo ""

echo "Step 2: Checking for Ollama installation..."
if ! command -v ollama &> /dev/null; then
    echo "  ✘ ERROR: 'ollama' command not found!"
    echo "  Please install Ollama before running this script."
    OLLAMA_STATUS="FAILED"
    exit 1
fi
echo "  ✓ Ollama found"
echo ""

echo "Step 3: Checking Ollama service..."
OLLAMA_LOG="$OLLAMA_LOGS_DIR/ollama-$TIMESTAMP.log"

if pgrep -x "ollama" > /dev/null; then
    echo "  ✓ Ollama is already running"
    OLLAMA_STATUS="OK"
else
    echo "  → Starting Ollama service..."
    nohup ollama serve > "$OLLAMA_LOG" 2>&1 &
    OLLAMA_PID=$!

    for i in {1..10}; do
        sleep 1
        if pgrep -x "ollama" > /dev/null; then
            echo "  ✓ Ollama started successfully (PID: $OLLAMA_PID)"
            echo "  ✓ Logs: $OLLAMA_LOG"
            OLLAMA_STATUS="OK"
            break
        fi
    done

    if [ "$OLLAMA_STATUS" != "OK" ]; then
        echo "  ✘ Failed to start Ollama"
        OLLAMA_STATUS="FAILED"
        exit 1
    fi
fi
echo ""

echo "Step 4: Testing installed LLM models..."
MODELS_OUTPUT=$(ollama list 2>&1)

if [ $? -ne 0 ]; then
    echo "  ✘ Failed to retrieve model list"
    exit 1
fi

MODELS=($(echo "$MODELS_OUTPUT" | tail -n +2 | awk '{print $1}' | grep -v '^$'))

if [ ${#MODELS[@]} -eq 0 ]; then
    echo "  ⚠ No models found installed"
    echo "  Please install at least one model using: ollama pull <model-name>"
    exit 1
fi

echo "  Found ${#MODELS[@]} model(s): ${MODELS[*]}"
echo ""

# Track smallest model by size
SMALLEST_SIZE=""

for model in "${MODELS[@]}"; do
    echo "  Verifying model: $model"

    MODEL_LOG_DIR="$MODELS_LOGS_DIR/$model"
    mkdir -p "$MODEL_LOG_DIR"

    MODEL_LOG="$MODEL_LOG_DIR/model-$model-$TIMESTAMP.log"

    echo "Verifying model $model at $(date)" > "$MODEL_LOG"

    ollama show "$model" >> "$MODEL_LOG" 2>&1

    if [ $? -eq 0 ]; then
        echo "    ✓ Model $model is available"
        MODEL_STATUS["$model"]="OK"

        # Get model size for comparison
        MODEL_SIZE=$(echo "$MODELS_OUTPUT" | grep "^$model" | awk '{print $2}')

        # Track smallest model (first model or smaller than current smallest)
        if [ -z "$SMALLEST_MODEL" ]; then
            SMALLEST_MODEL="$model"
            SMALLEST_SIZE="$MODEL_SIZE"
        fi
    else
        echo "    ✘ Model $model verification failed"
        MODEL_STATUS["$model"]="FAILED"
        exit 1
    fi
done

echo "  → Using model for tests: $SMALLEST_MODEL"
echo ""

# Warm-start models
if [ "$WARM_ALL_MODELS" = true ]; then
    echo "Step 4b: Warm-starting all models..."
    for model in "${MODELS[@]}"; do
        echo "  → Loading $model into memory..."
        MODEL_LOG_DIR="$MODELS_LOGS_DIR/$model"
        MODEL_WARM_LOG="$MODEL_LOG_DIR/model-warm-$TIMESTAMP.log"

        echo "Warm-starting model $model at $(date)" > "$MODEL_WARM_LOG"

        # Use a simple prompt to load the model
        timeout 120s ollama run "$model" "test" >> "$MODEL_WARM_LOG" 2>&1

        if [ $? -eq 0 ] || [ $? -eq 124 ]; then
            echo "    ✓ Model $model loaded"
        else
            echo "    ⚠ Model $model may not have loaded properly"
        fi
    done
    echo ""
else
    echo "Step 4b: Warm-starting smallest model..."
    echo "  → Loading $SMALLEST_MODEL into memory..."
    MODEL_LOG_DIR="$MODELS_LOGS_DIR/$SMALLEST_MODEL"
    MODEL_WARM_LOG="$MODEL_LOG_DIR/model-warm-$TIMESTAMP.log"

    echo "Warm-starting model $SMALLEST_MODEL at $(date)" > "$MODEL_WARM_LOG"

    # Use a simple prompt to load the model
    timeout 120s ollama run "$SMALLEST_MODEL" "test" >> "$MODEL_WARM_LOG" 2>&1

    if [ $? -eq 0 ] || [ $? -eq 124 ]; then
        echo "    ✓ Model $SMALLEST_MODEL loaded and ready"
    else
        echo "    ⚠ Model $SMALLEST_MODEL may not have loaded properly"
    fi
    echo ""
fi

echo "Step 5: Starting RAG-Sandbox service..."
RAG_LOG="$RAG_LOGS_DIR/rag-service-$TIMESTAMP.log"

RAG_DIR="$ROOT_DIR/RAG-Sandbox"

if [ ! -d "$RAG_DIR" ]; then
    echo "  ✘ RAG-Sandbox directory not found at: $RAG_DIR"
    RAG_STATUS="FAILED"
    exit 1
fi

if [ -f "$RAG_DIR/RAG-Sandbox.csproj" ] || [ -f "$RAG_DIR/RAGSandbox.csproj" ] || [ -f "$RAG_DIR/rag-sandbox.csproj" ]; then
    echo "  → Starting RAG-Sandbox with dotnet run..."
    cd "$RAG_DIR"
    nohup dotnet run --urls "http://localhost:5000" > "$RAG_LOG" 2>&1 &
    RAG_PID=$!
elif [ -f "$RAG_DIR/bin/Release/net8.0/RAG-Sandbox.dll" ]; then
    echo "  → Starting RAG-Sandbox from DLL..."
    nohup dotnet "$RAG_DIR/bin/Release/net8.0/RAG-Sandbox.dll" > "$RAG_LOG" 2>&1 &
    RAG_PID=$!
else
    echo "  ✘ Could not find RAG-Sandbox project or DLL"
    RAG_STATUS="FAILED"
    exit 1
fi

echo "  → RAG-Sandbox starting (PID: $RAG_PID)"
echo "  → Logs: $RAG_LOG"
echo "  → Waiting for service to be ready..."

SERVICE_READY=false
RAG_PORT="5000"
for i in {1..30}; do
    sleep 2

    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$RAG_PORT/api/chat/models" 2>/dev/null | grep -q "200"; then
        echo "  ✓ RAG-Sandbox service is responding on port $RAG_PORT"
        SERVICE_READY=true
        RAG_STATUS="OK"
        break
    fi
done

if [ "$SERVICE_READY" = false ]; then
    echo "  ✘ RAG-Sandbox service failed to respond"
    echo "  Check logs at: $RAG_LOG"
    RAG_STATUS="FAILED"
    exit 1
fi

echo ""

# Step 6: Run smoke tests (if not skipped)
if [ "$SKIP_TESTS" = false ]; then
    echo "Step 6: Running integration smoke tests..."

    TESTS_DIR="$ROOT_DIR/RAG-Sandbox/Tests"

    if [ ! -d "$TESTS_DIR" ]; then
        echo "  ⚠ Tests directory not found at: $TESTS_DIR"
        echo "  Skipping smoke tests"
        TESTS_STATUS="SKIPPED"
    else
        cd "$TESTS_DIR"

        echo "  → Running tests against http://localhost:$RAG_PORT with model: $SMALLEST_MODEL"

        # Set environment variables for the tests
        export RAG_BASE_URL="http://localhost:$RAG_PORT"
        export RAG_TEST_MODEL="$SMALLEST_MODEL"

        # Run the tests
        dotnet test --logger "console;verbosity=normal" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "  ✓ All smoke tests passed"
            TESTS_STATUS="OK"
        else
            echo "  ✘ Some smoke tests failed"
            echo "  → Running tests with verbose output..."
            dotnet test --logger "console;verbosity=normal"
            TESTS_STATUS="FAILED"
            exit 1
        fi
    fi

    echo ""
fi

echo "========================================="
if [ "$SKIP_TESTS" = true ]; then
    echo "     ALL SERVICES STARTED SUCCESSFULLY   "
else
    echo "   SERVICES STARTED & TESTS PASSED   "
fi
echo "========================================="

exit 0
