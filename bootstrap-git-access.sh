#!/usr/bin/env bash
set -Eeuo pipefail

# Public bootstrap script: installs GitHub access, then downloads and runs
# the private machine setup script from a private GitHub repo.
#
# Intended one-liner:
#   curl -fsSL https://raw.githubusercontent.com/EricEilberg/git-access/main/bootstrap-git-access.sh | bash

GITHUB_OWNER="${GITHUB_OWNER:-ecubed99}"
PRIVATE_REPO="${PRIVATE_REPO:-setup_files}"
PRIVATE_SCRIPT_PATH="${PRIVATE_SCRIPT_PATH:-setup-new-machine.sh}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
RUN_PRIVATE_SCRIPT="${RUN_PRIVATE_SCRIPT:-yes}"

usage() {
  cat <<USAGE
Usage: bootstrap-git-access.sh [options]

Options:
  --owner NAME             GitHub owner/user/org. Default: ${GITHUB_OWNER}
  --private-repo NAME      Private repo containing the real setup script. Default: ${PRIVATE_REPO}
  --private-script PATH    Script path inside private repo. Default: ${PRIVATE_SCRIPT_PATH}
  --ssh-key PATH           SSH private key path. Default: ${SSH_KEY_PATH}
  --no-run                 Do not download or run the private script.
  -h, --help               Show this help.

Environment variables are also supported:
  GITHUB_OWNER, PRIVATE_REPO, PRIVATE_SCRIPT_PATH, SSH_KEY_PATH, RUN_PRIVATE_SCRIPT
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      GITHUB_OWNER="$2"; shift 2 ;;
    --private-repo)
      PRIVATE_REPO="$2"; shift 2 ;;
    --private-script)
      PRIVATE_SCRIPT_PATH="$2"; shift 2 ;;
    --ssh-key)
      SSH_KEY_PATH="$2"; shift 2 ;;
    --no-run)
      RUN_PRIVATE_SCRIPT="no"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1 ;;
  esac
done

log() {
  # Send progress messages to stderr so functions can safely return data on stdout.
  printf '\n==> %s\n' "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1
}

ensure_apt() {
  if ! require_command apt; then
    echo "This bootstrap currently supports Debian/Ubuntu systems with apt." >&2
    exit 1
  fi
}

sudo_refresh() {
  if [[ ${EUID} -ne 0 ]]; then
    sudo -v
  fi
}

apt_install() {
  sudo apt update
  sudo apt install -y "$@"
}

install_github_cli() {
  if require_command gh; then
    return
  fi

  log "Installing GitHub CLI"
  apt_install curl wget git openssh-client ca-certificates gnupg lsb-release

  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt update
  sudo apt install -y gh
}

ensure_base_packages() {
  log "Installing bootstrap dependencies"
  apt_install curl wget git openssh-client ca-certificates
  install_github_cli
}

ensure_github_auth() {
  log "Checking GitHub authentication"
  if gh auth status >/dev/null 2>&1; then
    echo "Already authenticated with GitHub."
  else
    echo "GitHub device authentication will start now."
    echo "Copy the one-time code, then open the printed URL on another device."
    echo "Requesting access to the private setup repo and SSH public keys."
    # Feed the Enter prompt automatically and use echo as the browser command so
    # remote shells print the device-login URL instead of trying to launch a browser.
    printf '\n' | GH_BROWSER=echo gh auth login \
      --hostname github.com \
      --git-protocol ssh \
      --skip-ssh-key \
      --scopes repo,admin:public_key
  fi

  # Private-repo reads need repo. Managing account SSH keys additionally needs
  # admin:public_key. Refresh only when the key API shows that scope is missing.
  if ! gh api user/keys --silent >/dev/null 2>&1; then
    echo "GitHub authorization needs permission to manage SSH public keys."
    echo "Copy the one-time code, then open the printed URL on another device."
    printf '\n' | GH_BROWSER=echo gh auth refresh \
      --hostname github.com \
      --scopes repo,admin:public_key
  fi
}

ensure_ssh_key() {
  log "Ensuring SSH key exists and is uploaded to GitHub"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    ssh-keygen -t ed25519 \
      -C "${GITHUB_OWNER}@$(hostname)-$(date +%Y%m%d)" \
      -f "${SSH_KEY_PATH}" \
      -N ""
  else
    echo "SSH key already exists at ${SSH_KEY_PATH}."
  fi

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
  fi

  ssh-add "${SSH_KEY_PATH}" >/dev/null 2>&1 || true

  local public_key
  public_key="$(awk '{print $2}' "${SSH_KEY_PATH}.pub")"

  if gh ssh-key list 2>/dev/null | grep -q "$public_key"; then
    echo "SSH public key is already uploaded to GitHub."
  else
    gh ssh-key add "${SSH_KEY_PATH}.pub" --title "$(hostname)-$(date +%Y-%m-%d)"
  fi

  touch "$HOME/.ssh/known_hosts"
  ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts" 2>/dev/null || true
  chmod 600 "$HOME/.ssh/known_hosts"

  log "Testing SSH access to GitHub"
  local ssh_output
  local ssh_status
  set +e
  ssh_output="$(ssh -T -o BatchMode=yes git@github.com 2>&1)"
  ssh_status=$?
  set -e

  # GitHub intentionally returns status 1 after successful authentication.
  if [[ $ssh_status -eq 1 && "$ssh_output" == *"successfully authenticated"* ]]; then
    echo "$ssh_output"
  else
    echo "$ssh_output" >&2
    echo "SSH authentication to GitHub failed." >&2
    exit 1
  fi
}

download_private_script() {
  log "Downloading private setup script"
  local tmp_script
  tmp_script="$(mktemp -t private-setup.XXXXXX.sh)"

  gh api "repos/${GITHUB_OWNER}/${PRIVATE_REPO}/contents/${PRIVATE_SCRIPT_PATH}" \
    -H "Accept: application/vnd.github.raw" \
    > "$tmp_script"

  chmod 700 "$tmp_script"
  echo "$tmp_script"
}

main() {
  ensure_apt
  sudo_refresh
  ensure_base_packages
  ensure_github_auth
  ensure_ssh_key

  if [[ "$RUN_PRIVATE_SCRIPT" == "yes" ]]; then
    local private_script
    private_script="$(download_private_script)"

    log "Private script downloaded to ${private_script}"

    log "Running private setup script"
    GITHUB_OWNER="$GITHUB_OWNER" \
    PRIVATE_REPO="$PRIVATE_REPO" \
    bash "$private_script"
  else
    echo "Skipped running private script because --no-run was used."
  fi

  log "Bootstrap complete"
}

main "$@"
