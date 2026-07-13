# git-access

Public bootstrap repo for setting up Git and GitHub access on a new machine.

This repo contains only the minimal setup needed to authenticate with GitHub and reach a private setup repo. Personal preferences and machine configuration live in the private repo: `ecubed99/setup_files`.

## What this script does

`bootstrap-git-access.sh`:

1. Installs basic Git/GitHub dependencies on Ubuntu/Debian.
2. Installs GitHub CLI, `gh`.
3. Runs `gh auth login` when needed.
4. Creates an Ed25519 SSH key when one does not already exist.
5. Uploads the SSH public key to GitHub with `gh ssh-key add` when needed.
6. Tests SSH access to GitHub.
7. Optionally downloads and runs the complete setup script from the private `setup_files` repo.

## Usage

### Git access only

```bash
curl -fsSL https://raw.githubusercontent.com/ecubed99/git-access/main/bootstrap-git-access.sh | bash -s -- --no-run 
```

### Git access + full private setup

```bash
curl -fsSL https://raw.githubusercontent.com/ecubed99/git-access/main/bootstrap-git-access.sh | bash
```

This installs Git/GitHub access first, then downloads and runs:

```text
ecubed99/setup_files/setup-new-machine.sh
```

## Script options

```text
Usage: bootstrap-git-access.sh [mode] [options]

Modes:
  --git-only                  Install Git/GitHub access only. 
  
Options:
  --owner NAME              GitHub owner/user/org. Default: ecubed99
  --private-repo NAME       Private repo containing the real setup script. Default: setup_files
  --private-script PATH     Script path inside private repo. Default: setup-new-machine.sh
  --ssh-key PATH            SSH private key path. Default: ~/.ssh/id_ed25519
  -h, --help                Show help.
```

## Examples

Run the full setup using defaults:

```bash
curl -fsSL https://raw.githubusercontent.com/ecubed99/git-access/main/bootstrap-git-access.sh | bash 
```

Use a different private repo name:

```bash
curl -fsSL https://raw.githubusercontent.com/ecubed99/git-access/main/bootstrap-git-access.sh | bash -s -- --private-repo my_private_setup
```

Use a different SSH key path:

```bash
curl -fsSL https://raw.githubusercontent.com/ecubed99/git-access/main/bootstrap-git-access.sh | bash -s -- --git-only --ssh-key ~/.ssh/id_ed25519_github
```

Use a completely different account and repo setup:

```bash
curl -fsSL https://raw.githubusercontent.com/ecubed99/git-access/main/bootstrap-git-access.sh | bash -s -- \
    --owner your_git_account \
    --private-repo your_source_repo \
    --private-script your_setup_script
```
