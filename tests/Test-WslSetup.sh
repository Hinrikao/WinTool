#!/bin/bash
# Runs data/wsl-setup.sh in a plain Ubuntu container the way WinTool runs it
# in an existing WSL distro: as root, with the default user's uid. The
# ubuntu:24.04 image already has the user "ubuntu" (uid 1000) on bash.
set -eu
src="${1:-/src}"
fail() { echo "FAIL: $*"; exit 1; }

id ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash -u 1000 ubuntu
[ "$(getent passwd ubuntu | cut -d: -f7)" = "/bin/bash" ] || fail "the test user should start on bash"

run() {
  WINTOOL_SHELL_PROMPT="$1" WINTOOL_PROMPT_STYLE="${2:-}" WINTOOL_UID=1000 bash "${src}/data/wsl-setup.sh"
}

run oh-my-posh jandedobbeleer | tee /tmp/first.log
[ "$(getent passwd ubuntu | cut -d: -f7)" = "$(command -v zsh)" ] || fail "zsh is not the default shell"
[ -x /home/ubuntu/.local/bin/oh-my-posh ] || fail "oh-my-posh is missing"
[ -s /home/ubuntu/.config/wintool/jandedobbeleer.omp.json ] || fail "the theme is missing"
[ "$(grep -c '^# >>> WinTool >>>$' /home/ubuntu/.zshrc)" = "1" ] || fail "the WinTool block should appear once"
[ "$(stat -c %U /home/ubuntu/.zshrc)" = "ubuntu" ] || fail ".zshrc should belong to the user"
su - ubuntu -c "zsh -i -c 'whence -w _omp_precmd'" | grep -q function || fail "Oh My Posh did not load in zsh"

run oh-my-posh jandedobbeleer | tee /tmp/second.log
grep -q "already up to date" /tmp/second.log || fail "a second run should not change .zshrc"
[ "$(grep -c '^# >>> WinTool >>>$' /home/ubuntu/.zshrc)" = "1" ] || fail "a second run duplicated the block"

backups_before="$(ls /home/ubuntu/.zshrc.wintool-*.bak 2>/dev/null | wc -l)"
sleep 1
run pure | tee /tmp/third.log
grep -q '^ZSH_THEME=""' /home/ubuntu/.zshrc || fail "Pure needs ZSH_THEME empty"
grep -q 'prompt pure' /home/ubuntu/.zshrc || fail "the Pure block is missing"
grep -q 'oh-my-posh init' /home/ubuntu/.zshrc && fail "the old prompt block was not replaced"
[ "$(ls /home/ubuntu/.zshrc.wintool-*.bak | wc -l)" -gt "${backups_before}" ] || fail "a changed .zshrc needs a backup"

echo "WSL setup script passed."
