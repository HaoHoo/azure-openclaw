#!/bin/bash
# Placeholder: configure Tailscale tunnel for OpenClaw remote access.

echo "[openclaw] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo 'Please follow the instructions to log in to Tailscale and connect to your network.'
echo 'After setting up Tailscale, you can access OpenClaw remotely through the 
Tailscale IP address of this machine. Run "tailscale ip -4" to get the Tailscale IP address.'

