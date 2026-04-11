# Ref: https://github.com/openclaw/openclaw/blob/main/docs/vps.md

# If CLI commands feel slow on low-power VMs (or ARM hosts), enable Node's module compile cache
grep -q 'NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache' ~/.bashrc || cat >> ~/.bashrc <<'EOF'
export NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
mkdir -p /var/tmp/openclaw-compile-cache
export OPENCLAW_NO_RESPAWN=1
EOF
source ~/.bashrc

# modify systemd service to set environment variables and prevent respawn on failure, which can help with stability on low-power VMs or ARM hosts
sudo mkdir -p /etc/systemd/system/openclaw-gateway.service.d
sudo tee /etc/systemd/system/openclaw-gateway.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment=OPENCLAW_NO_RESPAWN=1
Environment=NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
Restart=always
RestartSec=2
TimeoutStartSec=90
EOF

sudo systemctl daemon-reload
sudo systemctl restart openclaw-gateway.service
sudo systemctl status openclaw-gateway.service --no-pager
