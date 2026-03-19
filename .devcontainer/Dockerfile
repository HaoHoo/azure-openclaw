FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN apt-get update && apt-get install -y curl ca-certificates git && apt-get clean
COPY install-azure-tools.sh /usr/local/bin/install-azure-tools.sh
RUN chmod +x /usr/local/bin/install-azure-tools.sh
