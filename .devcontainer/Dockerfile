FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Azure Developer CLI (azd)
RUN curl -fsSL https://aka.ms/install-azd.sh | bash

# Optional: Install Bicep explicitly (azd 会自动装，但你也可以手动装)
RUN az bicep install || true
