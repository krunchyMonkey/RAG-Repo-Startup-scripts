#!/bin/bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Check if Ollama is running
if ! pgrep -x "ollama" > /dev/null; then
    echo -e "${RED}Error: Ollama is not running${NC}"
    echo "Please start Ollama first"
    exit 1
fi

# Curated descriptions for popular models (static for quality info)
declare -A MODEL_DESCRIPTIONS
MODEL_DESCRIPTIONS["llama3.2"]="Latest Llama - Fast, efficient, great for general tasks"
MODEL_DESCRIPTIONS["llama3.1"]="Balanced performance and speed"
MODEL_DESCRIPTIONS["llama3"]="Meta's powerful general-purpose model"
MODEL_DESCRIPTIONS["mistral"]="Fast, high quality responses"
MODEL_DESCRIPTIONS["phi3"]="Microsoft's compact model, great quality/size ratio"
MODEL_DESCRIPTIONS["deepseek-r1"]="Strong reasoning, problem-solving focused"
MODEL_DESCRIPTIONS["deepseek-r1:14b"]="Strong reasoning, problem-solving focused"
MODEL_DESCRIPTIONS["deepseek-r1:70b"]="Advanced reasoning, handles complex problems"
MODEL_DESCRIPTIONS["deepseek-v3.2"]="Latest DeepSeek - Advanced reasoning and coding (641GB)"
MODEL_DESCRIPTIONS["deepseek-v3.1:671b"]="DeepSeek V3.1 - Massive 671B parameter model (641GB)"
MODEL_DESCRIPTIONS["mixtral"]="Mixture of experts, excellent performance"
MODEL_DESCRIPTIONS["qwen2.5"]="Alibaba's powerful model, excellent multilingual"
MODEL_DESCRIPTIONS["qwen2.5:32b"]="Alibaba's powerful model, excellent multilingual"
MODEL_DESCRIPTIONS["qwen2.5:72b"]="Top-tier performance, extensive knowledge"
MODEL_DESCRIPTIONS["qwen3-next:80b"]="Qwen3 next-gen - 80B parameter model, strong multilingual"
MODEL_DESCRIPTIONS["qwen3-coder:480b"]="Qwen3 Coder - Massive 480B coding specialist (475GB)"
MODEL_DESCRIPTIONS["qwen3-vl:235b"]="Qwen3 Vision-Language - Multimodal 235B model (438GB)"
MODEL_DESCRIPTIONS["qwen3-vl:235b-instruct"]="Qwen3 VL Instruct - Instruction-tuned multimodal (438GB)"
MODEL_DESCRIPTIONS["codellama"]="Optimized for code generation and debugging"
MODEL_DESCRIPTIONS["deepseek-coder"]="Advanced coding assistant"
MODEL_DESCRIPTIONS["deepseek-coder-v2"]="Next-gen coding assistant with improved accuracy"
MODEL_DESCRIPTIONS["llama3.2-vision"]="Multimodal - can process images and text"
MODEL_DESCRIPTIONS["gemma"]="Google's efficient open model"
MODEL_DESCRIPTIONS["gemma2"]="Google's latest efficient model"
MODEL_DESCRIPTIONS["gemma3:4b"]="Google Gemma3 4B - Compact and efficient"
MODEL_DESCRIPTIONS["gemma3:12b"]="Google Gemma3 12B - Balanced performance"
MODEL_DESCRIPTIONS["gemma3:27b"]="Google Gemma3 27B - High performance variant"
MODEL_DESCRIPTIONS["gpt-oss:20b"]="Open-source GPT-style 20B parameter model"
MODEL_DESCRIPTIONS["gpt-oss:120b"]="Open-source GPT-style 120B parameter model"
MODEL_DESCRIPTIONS["ministral-3:3b"]="Ministral 3B - Small and fast"
MODEL_DESCRIPTIONS["ministral-3:8b"]="Ministral 8B - Balanced performance"
MODEL_DESCRIPTIONS["ministral-3:14b"]="Ministral 14B - Enhanced capabilities"
MODEL_DESCRIPTIONS["command-r"]="Cohere's retrieval-augmented model"
MODEL_DESCRIPTIONS["neural-chat"]="Intel's optimized chat model"
MODEL_DESCRIPTIONS["vicuna"]="Fine-tuned LLaMA variant, conversational"
MODEL_DESCRIPTIONS["orca-mini"]="Compact reasoning model"
MODEL_DESCRIPTIONS["yi"]="01.AI's multilingual model"
MODEL_DESCRIPTIONS["solar"]="Upstage's high-performance model"

# Fetch available models from Ollama API with loading indicator
echo -n "Fetching available models from Ollama registry"

# Show loading animation
(
    while kill -0 $$ 2>/dev/null; do
        for s in / - \\ \|; do
            echo -ne "\rFetching available models from Ollama registry $s"
            sleep 0.2
        done
    done
) &
SPINNER_PID=$!

MODELS_JSON=$(curl -s 'https://ollama.com/api/tags' 2>/dev/null)
CURL_EXIT=$?

# Stop spinner
kill $SPINNER_PID 2>/dev/null
wait $SPINNER_PID 2>/dev/null

if [ $CURL_EXIT -ne 0 ] || [ -z "$MODELS_JSON" ]; then
    echo -e "\r${RED}Error: Could not fetch models from Ollama registry${NC}     "
    echo "Using offline mode with limited model list"
    OFFLINE_MODE=true
else
    echo -e "\r${GREEN}✓ Fetched available models successfully${NC}          "
    sleep 0.5
    OFFLINE_MODE=false
fi

declare -A AVAILABLE_MODELS
declare -A MODEL_SIZES

# Parse JSON and populate arrays
if [ "$OFFLINE_MODE" = false ]; then
    # Extract model entries properly (name and size together)
    while IFS= read -r entry; do
        if [ -n "$entry" ]; then
            # Extract name
            if [[ $entry =~ \"name\":\"([^\"]+)\" ]]; then
                model_name="${BASH_REMATCH[1]}"
            fi

            # Extract size
            if [[ $entry =~ \"size\":([0-9]+) ]]; then
                size_bytes="${BASH_REMATCH[1]}"

                # Convert bytes to GB
                size_gb=$(echo "scale=1; $size_bytes / 1073741824" | bc 2>/dev/null || echo "0")

                # Only include models under 700GB for practical use
                if (( $(echo "$size_gb > 0 && $size_gb < 700" | bc -l 2>/dev/null || echo 0) )); then
                    AVAILABLE_MODELS["$model_name"]=1
                    MODEL_SIZES["$model_name"]="${size_gb} GB"
                fi
            fi
        fi
    done < <(echo "$MODELS_JSON" | grep -oP '"name":"[^"]+","model":"[^"]+","modified_at":"[^"]+","size":[0-9]+')
fi

# Categorize models by size
categorize_model() {
    local size=$1
    local size_num=$(echo "$size" | grep -oP '^\d+\.?\d*')

    if (( $(echo "$size_num < 5" | bc -l) )); then
        echo "Small & Fast"
    elif (( $(echo "$size_num < 15" | bc -l) )); then
        echo "Medium & Powerful"
    elif (( $(echo "$size_num < 50" | bc -l) )); then
        echo "Large & Advanced"
    else
        echo "Enterprise"
    fi
}

# Get installed models
get_installed_models() {
    ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$'
}

# Get loaded models
get_loaded_models() {
    ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$'
}

# Check if model is installed
is_installed() {
    local model=$1
    local installed=$(get_installed_models)
    echo "$installed" | grep -q "^${model}$"
}

# Check if model is loaded
is_loaded() {
    local model=$1
    local loaded=$(get_loaded_models)
    echo "$loaded" | grep -q "^${model}$"
}

# Build menu items
build_menu() {
    MENU_ITEMS=()
    MENU_TYPES=()

    # Installed models section
    local installed=$(get_installed_models)
    if [ -n "$installed" ]; then
        MENU_ITEMS+=("═══ INSTALLED MODELS ═══")
        MENU_TYPES+=("header")

        while IFS= read -r model; do
            MENU_ITEMS+=("$model")
            MENU_TYPES+=("installed")
        done <<< "$installed"

        MENU_ITEMS+=("")
        MENU_TYPES+=("spacer")
    fi

    # Available models by category
    MENU_ITEMS+=("═══ AVAILABLE TO DOWNLOAD ═══")
    MENU_TYPES+=("header")

    if [ "$OFFLINE_MODE" = true ]; then
        MENU_ITEMS+=("${DIM}(Offline - cannot fetch model list)${NC}")
        MENU_TYPES+=("info")
    else
        # Group by category
        declare -A category_models

        for model in "${!AVAILABLE_MODELS[@]}"; do
            if ! is_installed "$model"; then
                size="${MODEL_SIZES[$model]}"
                category=$(categorize_model "$size")
                category_models["$category"]+="$model|"
            fi
        done

        for category in "Small & Fast" "Medium & Powerful" "Large & Advanced" "Enterprise"; do
            if [ -n "${category_models[$category]:-}" ]; then
                MENU_ITEMS+=("─── $category ───")
                MENU_TYPES+=("category")

                IFS='|' read -ra models <<< "${category_models[$category]}"
                local count=0
                for model in $(printf '%s\n' "${models[@]}" | sort); do
                    if [ -n "$model" ] && [ $count -lt 10 ]; then
                        MENU_ITEMS+=("$model")
                        MENU_TYPES+=("available")
                        ((count++))
                    fi
                done

                # Show "more available" if there are more than 10
                local total_in_category=$(printf '%s\n' "${models[@]}" | grep -v '^$' | wc -l)
                if [ $total_in_category -gt 10 ]; then
                    local remaining=$((total_in_category - 10))
                    MENU_ITEMS+=("${DIM}... and $remaining more models in this category${NC}")
                    MENU_TYPES+=("info")
                fi
            fi
        done
    fi
}

# Display menu
show_menu() {
    clear
    echo "========================================="
    echo "       OLLAMA MODEL MANAGER"
    echo "========================================="
    echo ""

    for i in "${!MENU_ITEMS[@]}"; do
        local item="${MENU_ITEMS[$i]}"
        local type="${MENU_TYPES[$i]}"

        case "$type" in
            header)
                echo -e "${BOLD}${CYAN}$item${NC}"
                ;;
            category)
                echo ""
                echo -e "${DIM}$item${NC}"
                ;;
            spacer)
                echo ""
                ;;
            info)
                echo -e "$item"
                ;;
            installed)
                local prefix="  "
                if [ $i -eq $1 ]; then
                    prefix="${BOLD}${CYAN}▶ ${NC}"
                fi

                if is_loaded "$item"; then
                    echo -e "${prefix}${GREEN}● ${item}${NC} ${DIM}(loaded)${NC}"
                else
                    echo -e "${prefix}${YELLOW}○ ${item}${NC} ${DIM}(not loaded)${NC}"
                fi
                ;;
            available)
                local prefix="  "
                if [ $i -eq $1 ]; then
                    prefix="${BOLD}${CYAN}▶ ${NC}"
                fi

                local size="${MODEL_SIZES[$item]:-Unknown}"
                local desc="${MODEL_DESCRIPTIONS[$item]:-New model - no description available}"
                echo -e "${prefix}${MAGENTA}⬇ ${item}${NC} ${DIM}[$size]${NC}"
                if [ $i -eq $1 ]; then
                    echo -e "     ${DIM}$desc${NC}"
                fi
                ;;
        esac
    done

    echo ""
    echo "========================================="
    echo "↑/↓: Navigate  | Enter: Select | q: Quit"
    echo "========================================="
}

# Load model
load_model() {
    local model=$1
    echo ""
    echo -e "${CYAN}Loading model: ${BOLD}$model${NC}"
    echo "This may take a few moments..."

    timeout 120s ollama run "$model" "test" > /dev/null 2>&1

    if [ $? -eq 0 ] || [ $? -eq 124 ]; then
        echo -e "${GREEN}✓ Model $model loaded successfully${NC}"
        sleep 1
    else
        echo -e "${RED}✘ Failed to load model $model${NC}"
        sleep 2
    fi
}

# Download model
download_model() {
    local model=$1
    echo ""
    echo -e "${CYAN}Downloading model: ${BOLD}$model${NC}"
    echo -e "${DIM}Size: ${MODEL_SIZES[$model]:-Unknown}${NC}"
    echo ""

    ollama pull "$model"

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Model $model downloaded successfully${NC}"
        sleep 2
    else
        echo ""
        echo -e "${RED}✘ Failed to download model $model${NC}"
        sleep 2
    fi
}

# Confirm action
confirm_action() {
    local model=$1
    local action=$2

    echo ""

    case "$action" in
        load)
            echo -e "${CYAN}Load model '${BOLD}$model${NC}${CYAN}' into memory?${NC}"
            echo ""
            read -p "Continue? [y/N]: " -n 1 -r
            ;;
        loaded)
            echo -e "${YELLOW}Model '${BOLD}$model${NC}${YELLOW}' is already loaded.${NC}"
            echo ""
            echo "Note: Models auto-unload after inactivity."
            read -p "Press Enter to continue..." dummy
            return 1
            ;;
        download)
            echo -e "${CYAN}Download model '${BOLD}$model${NC}${CYAN}'?${NC}"
            echo -e "${DIM}Size: ${MODEL_SIZES[$model]:-Unknown}${NC}"
            local desc="${MODEL_DESCRIPTIONS[$model]:-New model}"
            echo -e "${DIM}$desc${NC}"
            echo ""
            read -p "This will download the model. Continue? [y/N]: " -n 1 -r
            ;;
    esac

    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "Cancelled."
        sleep 1
        return 1
    fi
}

# Main loop
build_menu
selected=0
total=${#MENU_ITEMS[@]}

# Find first selectable item
while [ $selected -lt $total ]; do
    type="${MENU_TYPES[$selected]}"
    if [ "$type" = "installed" ] || [ "$type" = "available" ]; then
        break
    fi
    ((selected++))
done

while true; do
    show_menu $selected

    read -rsn1 key

    case "$key" in
        $'\x1b')
            read -rsn2 key
            case "$key" in
                '[A')  # Up
                    old_selected=$selected
                    ((selected--))
                    while [ $selected -ge 0 ]; do
                        type="${MENU_TYPES[$selected]}"
                        if [ "$type" = "installed" ] || [ "$type" = "available" ]; then
                            break
                        fi
                        ((selected--))
                    done
                    if [ $selected -lt 0 ]; then
                        selected=$old_selected
                    fi
                    ;;
                '[B')  # Down
                    old_selected=$selected
                    ((selected++))
                    while [ $selected -lt $total ]; do
                        type="${MENU_TYPES[$selected]}"
                        if [ "$type" = "installed" ] || [ "$type" = "available" ]; then
                            break
                        fi
                        ((selected++))
                    done
                    if [ $selected -ge $total ]; then
                        selected=$old_selected
                    fi
                    ;;
            esac
            ;;
        '')  # Enter
            model="${MENU_ITEMS[$selected]}"
            type="${MENU_TYPES[$selected]}"

            clear

            if [ "$type" = "installed" ]; then
                if is_loaded "$model"; then
                    confirm_action "$model" "loaded"
                else
                    if confirm_action "$model" "load"; then
                        load_model "$model"
                    fi
                fi
            elif [ "$type" = "available" ]; then
                if confirm_action "$model" "download"; then
                    download_model "$model"
                    build_menu
                fi
            fi
            ;;
        q|Q)
            clear
            echo "Exiting model manager."
            exit 0
            ;;
    esac
done
