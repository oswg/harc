#!/bin/bash
# All-in-one GitLab server setup for Ubuntu 24.04 LTS (Noble)
#
# Bootstraps host hardening (SSH key-only on port 24197, UFW, fail2ban,
# unattended security upgrades) then installs GitLab EE, Pages, Runner, and Docker.
#
# Required environment variables:
#   ADMIN_SSH_PUBLIC_KEY  Public key for the admin SSH user (key-only auth)
#
# Optional environment variables:
#   ADMIN_USER                  Admin SSH user (default: deploy)
#   ADMIN_IP                    If set, UFW allows SSH only from this CIDR (e.g. 203.0.113.10/32)
#   GITLAB_EXTERNAL_URL         GitLab URL (default: https://gitlab.example.com)
#   GITLAB_PAGES_URL            Pages URL — must NOT be a subdomain of GITLAB_EXTERNAL_URL
#   GITLAB_ROOT_PASSWORD        GitLab root password (min 8 chars; random if unset)
#   GITLAB_ENABLE_LETSENCRYPT   Set to 1 to enable Let's Encrypt in gitlab.rb
#   GITLAB_LETSENCRYPT_EMAIL    Contact email for Let's Encrypt (required if LE enabled)
#   SSH_PORT                    SSH port (default: 24197)
#
# Run on the Ubuntu 24.04 server (via SSH), not on your laptop.
#
# Example:
#   ssh root@your-server
#   export ADMIN_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
#   export ADMIN_USER=deploy
#   export ADMIN_IP=203.0.113.10/32
#   export GITLAB_EXTERNAL_URL=https://git.example.com
#   export GITLAB_PAGES_URL=https://pages.example.io
#   export GITLAB_ENABLE_LETSENCRYPT=1
#   export GITLAB_LETSENCRYPT_EMAIL=admin@example.com
#   sudo -E ./scripts/setup_gitlab_server.sh
#
# After install: sign in at GITLAB_EXTERNAL_URL as root, register runner from
#   Admin > CI/CD > Runners

set -euo pipefail

# === Configuration ===
ADMIN_USER="${ADMIN_USER:-deploy}"
ADMIN_SSH_PUBLIC_KEY="${ADMIN_SSH_PUBLIC_KEY:-}"
ADMIN_IP="${ADMIN_IP:-}"
GITLAB_EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-https://gitlab.example.com}"
GITLAB_PAGES_URL="${GITLAB_PAGES_URL:-https://pages.example.io}"
GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-}"
GITLAB_ENABLE_LETSENCRYPT="${GITLAB_ENABLE_LETSENCRYPT:-0}"
GITLAB_LETSENCRYPT_EMAIL="${GITLAB_LETSENCRYPT_EMAIL:-}"
SSH_PORT="${SSH_PORT:-24197}"
UBUNTU_CODENAME="noble"  # Ubuntu 24.04 LTS

SSHD_DROPIN="/etc/ssh/sshd_config.d/99-gitlab-setup.conf"
GITLAB_RB="/etc/gitlab/gitlab.rb"
GITLAB_RB_BEGIN="# === gitlab-setup-script BEGIN ==="
GITLAB_RB_END="# === gitlab-setup-script END ==="

log() { echo "=== $* ==="; }

require_root() {
  [[ $EUID -eq 0 ]] || { echo "Run as root: sudo -E $0"; exit 1; }
}

preflight() {
  log "Preflight checks"
  require_root

  if [[ -z "$ADMIN_SSH_PUBLIC_KEY" ]]; then
    echo "ERROR: ADMIN_SSH_PUBLIC_KEY is required (key-only SSH)."
    echo "  export ADMIN_SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_ed25519.pub)\""
    exit 1
  fi

  if [[ "$GITLAB_ENABLE_LETSENCRYPT" == "1" && -z "$GITLAB_LETSENCRYPT_EMAIL" ]]; then
    echo "ERROR: GITLAB_LETSENCRYPT_EMAIL is required when GITLAB_ENABLE_LETSENCRYPT=1"
    exit 1
  fi

  if [[ -d /etc/gitlab ]]; then
    echo "WARNING: /etc/gitlab exists — continuing with idempotent updates."
  fi

  echo ""
  echo "IMPORTANT: Keep a console/VNC session open until SSH on port ${SSH_PORT} is verified."
  echo ""
}

install_base_packages() {
  log "Installing base packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl ca-certificates ufw fail2ban unattended-upgrades apt-listchanges
}

setup_admin_user() {
  log "Creating admin user: ${ADMIN_USER}"
  if ! id "$ADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$ADMIN_USER"
  fi
  usermod -aG sudo "$ADMIN_USER"

  local ssh_dir="/home/${ADMIN_USER}/.ssh"
  install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$ssh_dir"
  local auth_keys="${ssh_dir}/authorized_keys"
  touch "$auth_keys"
  chown "$ADMIN_USER:$ADMIN_USER" "$auth_keys"
  chmod 600 "$auth_keys"

  if ! grep -qF "$ADMIN_SSH_PUBLIC_KEY" "$auth_keys"; then
    echo "$ADMIN_SSH_PUBLIC_KEY" >> "$auth_keys"
  fi
}

setup_sshd() {
  log "Hardening SSH (port ${SSH_PORT}, key-only)"
  cat > "$SSHD_DROPIN" <<EOF
# Managed by setup_gitlab_server.sh — do not edit by hand
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AllowUsers ${ADMIN_USER} git
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
EOF
  chmod 644 "$SSHD_DROPIN"

  sshd -t
  systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  echo "SSH listening on port ${SSH_PORT} (users: ${ADMIN_USER}, git). Verify before closing this session."
}

setup_ufw() {
  log "Configuring UFW"
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw logging medium
  ufw allow 80/tcp
  ufw allow 443/tcp

  if [[ -n "$ADMIN_IP" ]]; then
    ufw allow from "$ADMIN_IP" to any port "${SSH_PORT}" proto tcp
  else
    ufw allow "${SSH_PORT}"/tcp
  fi

  ufw --force enable
}

setup_fail2ban() {
  log "Configuring fail2ban"
  cat > /etc/fail2ban/jail.d/sshd-local.conf <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 5
bantime = 1h
findtime = 10m
EOF
  systemctl enable fail2ban
  systemctl restart fail2ban
}

setup_sysctl() {
  log "Applying sysctl hardening"
  cat > /etc/sysctl.d/99-gitlab-setup.conf <<'EOF'
# Managed by setup_gitlab_server.sh
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF
  sysctl --system >/dev/null
}

setup_unattended_upgrades() {
  log "Enabling unattended security upgrades"
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
  systemctl enable unattended-upgrades 2>/dev/null || true
}

setup_timezone() {
  log "Setting timezone to UTC"
  timedatectl set-timezone UTC || true
}

update_gitlab_rb() {
  log "Updating ${GITLAB_RB}"
  if [[ ! -f "$GITLAB_RB" ]]; then
    touch "$GITLAB_RB"
  fi

  if grep -q "$GITLAB_RB_BEGIN" "$GITLAB_RB"; then
    sed -i "/${GITLAB_RB_BEGIN}/,/${GITLAB_RB_END}/d" "$GITLAB_RB"
  fi

  {
    echo ""
    echo "$GITLAB_RB_BEGIN"
    echo "gitlab_rails['gitlab_shell_ssh_port'] = ${SSH_PORT}"
    echo "pages_external_url '${GITLAB_PAGES_URL}'"
    if [[ "$GITLAB_ENABLE_LETSENCRYPT" == "1" ]]; then
      echo "nginx['redirect_http_to_https'] = true"
      echo "letsencrypt['enable'] = true"
      echo "letsencrypt['contact_emails'] = ['${GITLAB_LETSENCRYPT_EMAIL}']"
    fi
    echo "$GITLAB_RB_END"
  } >> "$GITLAB_RB"
}

install_gitlab() {
  log "Installing GitLab EE"
  if ! grep -q packages.gitlab.com/gitlab/gitlab-ee /etc/apt/sources.list.d/* 2>/dev/null; then
    curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh" | bash
  fi

  export EXTERNAL_URL="$GITLAB_EXTERNAL_URL"
  [[ -n "$GITLAB_ROOT_PASSWORD" ]] && export GITLAB_ROOT_PASSWORD

  if ! dpkg -s gitlab-ee &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ee
  fi

  update_gitlab_rb
  gitlab-ctl reconfigure
}

install_docker() {
  if command -v docker &>/dev/null; then
    echo "Docker already installed."
    return
  fi

  log "Installing Docker"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io
}

install_runner() {
  log "Installing GitLab Runner"
  if ! grep -q packages.gitlab.com/runner/gitlab-runner /etc/apt/sources.list.d/* 2>/dev/null; then
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-runner
  usermod -aG docker gitlab-runner 2>/dev/null || true
}

print_summary() {
  local pages_host
  pages_host="$(echo "$GITLAB_PAGES_URL" | sed -E 's|https?://||' | cut -d/ -f1)"
  local hostname_hint
  hostname_hint="$(hostname -f 2>/dev/null || hostname)"

  echo ""
  log "Setup complete"
  echo ""
  echo "Admin SSH:  ssh -p ${SSH_PORT} ${ADMIN_USER}@${hostname_hint}"
  echo "Git SSH:    ssh -p ${SSH_PORT} git@${hostname_hint}"
  echo "GitLab URL: ${GITLAB_EXTERNAL_URL}"
  echo "Pages URL:  ${GITLAB_PAGES_URL}"
  echo "SSH port:   ${SSH_PORT} (port 22 is not opened in UFW)"
  echo ""
  echo "Security:"
  echo "  - Key-only SSH for ${ADMIN_USER}; root login disabled"
  echo "  - UFW: deny incoming except 80, 443, ${SSH_PORT}"
  [[ -n "$ADMIN_IP" ]] && echo "  - SSH restricted to: ${ADMIN_IP}"
  echo "  - fail2ban enabled for sshd on port ${SSH_PORT}"
  echo ""
  echo "Next steps:"
  echo "  1. Point DNS for GitLab and Pages to this server's IP"
  echo "  2. Pages wildcard: *.${pages_host} -> this IP"
  echo "  3. Sign in as root at ${GITLAB_EXTERNAL_URL}"
  echo "  4. Root password: /etc/gitlab/initial_root_password (if GITLAB_ROOT_PASSWORD was unset)"
  echo "  5. Register runner: Admin > CI/CD > Runners, then:"
  echo "       sudo gitlab-runner register --url ${GITLAB_EXTERNAL_URL} --token <token> --executor docker"
  echo "  6. Schedule GitLab backups (not configured by this script)"
  echo ""
  echo "If you lose your SSH key, use the provider console to recover access."
  echo ""
}

main() {
  preflight
  install_base_packages
  setup_admin_user
  setup_sshd
  setup_ufw
  setup_fail2ban
  setup_sysctl
  setup_unattended_upgrades
  setup_timezone
  install_gitlab
  install_docker
  install_runner
  print_summary
}

main "$@"
