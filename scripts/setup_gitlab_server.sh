#!/bin/bash
# GitLab server setup: Ubuntu + GitLab EE + Pages + Runner + SSH on port 24197
#
# Prerequisites: Ubuntu 22.04 or 24.04, root/sudo
#
# Before running, set these variables (or edit below):
#   GITLAB_EXTERNAL_URL   - e.g. https://git.example.com
#   GITLAB_PAGES_URL      - e.g. https://pages.example.io (must NOT be subdomain of GITLAB_EXTERNAL_URL)
#   GITLAB_ROOT_PASSWORD  - min 8 chars (optional; random one generated if unset)
#
# Usage: sudo ./setup_gitlab_server.sh
#
# After install: sign in at GITLAB_EXTERNAL_URL as root, get runner token from
#   Admin > CI/CD > Runners, then run: sudo gitlab-runner register --url $GITLAB_EXTERNAL_URL --token <token>

set -e

# === CONFIGURE THESE ===
GITLAB_EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-https://gitlab.example.com}"
GITLAB_PAGES_URL="${GITLAB_PAGES_URL:-https://pages.example.io}"
GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-}"
SSH_PORT=24197

# === Check root ===
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

echo "=== Installing GitLab with Pages and SSH port $SSH_PORT ==="

# === Firewall: enable ufw, allow HTTP/HTTPS/SSH (custom port) ===
apt-get update
apt-get install -y curl ufw
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${SSH_PORT}/tcp
ufw --force enable || true

# === System SSH: change port to 24197 ===
sed -i "s/^#*Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config || echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config
systemctl enable --now ssh
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
echo "SSH now on port $SSH_PORT. Ensure you have another session or console before disconnecting."

# === Add GitLab package repository ===
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh" | bash

# === Install GitLab ===
export EXTERNAL_URL="$GITLAB_EXTERNAL_URL"
[[ -n "$GITLAB_ROOT_PASSWORD" ]] && export GITLAB_ROOT_PASSWORD
apt-get install -y gitlab-ee

# === Configure gitlab.rb (appends; run once on fresh install) ===
RB="/etc/gitlab/gitlab.rb"
if ! grep -q "gitlab_shell_ssh_port" "$RB"; then
  echo ""
  echo "# === Setup script: SSH port + Pages ===" >> "$RB"
  echo "gitlab_rails['gitlab_shell_ssh_port'] = ${SSH_PORT}" >> "$RB"
  echo "pages_external_url '${GITLAB_PAGES_URL}'" >> "$RB"
fi

# Reconfigure
gitlab-ctl reconfigure

# === Install GitLab Runner ===
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
apt-get install -y gitlab-runner

# Docker for runner (optional; for Docker executor)
if command -v docker &>/dev/null; then
  echo "Docker already installed."
else
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io
  usermod -aG docker gitlab-runner
fi

echo ""
echo "=== GitLab installed ==="
echo "URL:     $GITLAB_EXTERNAL_URL"
echo "Pages:   $GITLAB_PAGES_URL"
echo "SSH:     port $SSH_PORT (ssh -p $SSH_PORT git@your-server)"
echo ""
echo "Next steps:"
echo "1. Point DNS: your domains to this server's IP"
echo "2. For Pages: add wildcard DNS *.$(echo $GITLAB_PAGES_URL | sed -E 's|https?://||' | cut -d/ -f1) -> this IP"
echo "3. Sign in as root at $GITLAB_EXTERNAL_URL"
echo "4. Root password: /etc/gitlab/initial_root_password (if not set)"
echo "5. Register runner: Admin > CI/CD > Runners, copy token, then:"
echo "   sudo gitlab-runner register --url $GITLAB_EXTERNAL_URL --token <token> --executor docker"
echo ""
