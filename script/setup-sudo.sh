#!/bin/bash

# This script configures sudo to allow stopping Ollama without a password
# Run this ONCE with: sudo ./script/setup-sudo.sh

set -e

SUDOERS_FILE="/etc/sudoers.d/ollama-control"
CURRENT_USER="$SUDO_USER"

if [ -z "$CURRENT_USER" ]; then
    CURRENT_USER="$USER"
fi

echo "Setting up passwordless sudo for Ollama control..."
echo "User: $CURRENT_USER"

# Create sudoers file
cat > "$SUDOERS_FILE" << EOF
# Allow $CURRENT_USER to control Ollama service without password
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl start ollama
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop ollama
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart ollama
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl status ollama
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/kill -TERM *
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/kill -9 *
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill -9 -x ollama
EOF

# Set proper permissions
chmod 0440 "$SUDOERS_FILE"

echo "✓ Sudo configuration created: $SUDOERS_FILE"
echo "✓ You can now run stop.sh and start.sh without entering a password for Ollama control"
