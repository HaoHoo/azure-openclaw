#!/usr/bin/env bash
set -e

echo ">>> Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash || echo "Azure CLI install failed"

echo ">>> Installing Azure Developer CLI (azd)..."
curl -fsSL https://aka.ms/install-azd.sh | bash || echo "azd install failed"

echo ">>> Installing Bicep CLI..."
az bicep install || echo "bicep install failed"

echo ">>> Azure tools installation finished."
