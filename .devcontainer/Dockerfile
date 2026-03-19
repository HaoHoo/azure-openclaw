FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN sudo rm /etc/apt/sources.list.d/yarn.list
RUN sudo apt-get update && sudo apt-get install -y curl ca-certificates git && sudo apt-get clean
COPY .devcontainer/install-azure-tools.sh /usr/local/bin/install-azure-tools.sh
RUN sudo chmod +x /usr/local/bin/install-azure-tools.sh
