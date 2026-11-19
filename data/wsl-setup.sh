#!/bin/bash
# WinTool optional shell setup inside WSL. Safe to run more than once.
set -eu

echo "WinTool: installing zsh"

if command -v apt-get >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zsh git curl
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y zsh git curl
else
  echo "WinTool: this distro needs zsh, git, and curl installed first."
  exit 1
fi

if [ ! -d "${HOME}/.oh-my-zsh" ]; then
  echo "WinTool: installing Oh My Zsh"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

zsh_path="$(command -v zsh)"
if [ -n "${zsh_path}" ] && [ "${SHELL}" != "${zsh_path}" ]; then
  chsh -s "${zsh_path}" || echo "WinTool: could not change the default shell. Run: chsh -s ${zsh_path}"
fi

echo "WinTool: zsh setup finished"
