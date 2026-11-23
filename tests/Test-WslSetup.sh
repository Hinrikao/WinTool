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
  WINTOOL_SHELL_PROMPT="$1" WINTOOL_PROMPT_STYLE="${2:-}" WINTOOL_STYLE_FILE="${3:-}" WINTOOL_STYLE_SETTINGS="${4:-}" WINTOOL_UID=1000 bash "${src}/data/wsl-setup.sh"
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

# Prompt styles (data/terminal.json "promptVariants").
run powerlevel10k rainbow config/p10k-rainbow.zsh | tee /tmp/p10k.log
grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' /home/ubuntu/.zshrc || fail "Powerlevel10k is not the Oh My Zsh theme"
cmp -s /home/ubuntu/.oh-my-zsh/custom/themes/powerlevel10k/config/p10k-rainbow.zsh /home/ubuntu/.p10k.zsh || fail "~/.p10k.zsh is not the Rainbow style"
grep -q 'source "$HOME/.p10k.zsh"' /home/ubuntu/.zshrc || fail ".zshrc does not load ~/.p10k.zsh"
grep -q 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' /home/ubuntu/.zshrc || fail "the Powerlevel10k wizard is not turned off"
[ "$(stat -c %U /home/ubuntu/.p10k.zsh)" = "ubuntu" ] || fail "~/.p10k.zsh should belong to the user"
run powerlevel10k lean | tee /tmp/p10k-lean.log
cmp -s /home/ubuntu/.oh-my-zsh/custom/themes/powerlevel10k/config/p10k-lean.zsh /home/ubuntu/.p10k.zsh || fail "switching to Lean did not replace ~/.p10k.zsh"
ls /home/ubuntu/.p10k.zsh.wintool-*.bak >/dev/null 2>&1 || fail "the old ~/.p10k.zsh needs a backup"
su - ubuntu -c "zsh -i -c 'echo \$POWERLEVEL9K_MODE; typeset -p POWERLEVEL9K_LEFT_PROMPT_ELEMENTS'" </dev/null > /tmp/p10k-zsh.log 2>&1 || true
grep -q 'POWERLEVEL9K_LEFT_PROMPT_ELEMENTS' /tmp/p10k-zsh.log || { cat /tmp/p10k-zsh.log; fail "Powerlevel10k did not load the style in zsh"; }

run spaceship single-line "" "SPACESHIP_PROMPT_SEPARATE_LINE=false" | tee /tmp/spaceship.log
grep -q '^ZSH_THEME="spaceship"' /home/ubuntu/.zshrc || fail "Spaceship is not the Oh My Zsh theme"
grep -qx 'SPACESHIP_PROMPT_SEPARATE_LINE=false' /home/ubuntu/.zshrc || fail "the Spaceship style setting is missing"
grep -q 'p10k.zsh' /home/ubuntu/.zshrc && fail "the Powerlevel10k block was not replaced"

run pure git-stash "" "zstyle :prompt:pure:git:stash show yes" | tee /tmp/pure-style.log
grep -q 'zstyle :prompt:pure:git:stash show yes' /home/ubuntu/.zshrc || fail "the Pure style setting is missing"
run pure default "" "touch /tmp/owned; echo bad" | tee /tmp/pure-bad.log
grep -q 'touch /tmp/owned' /home/ubuntu/.zshrc && fail "an unsafe setting line reached .zshrc"

run tide classic | tee /tmp/tide.log
[ "$(getent passwd ubuntu | cut -d: -f7)" = "$(command -v fish)" ] || fail "fish is not the default shell for Tide"
vars=/home/ubuntu/.config/fish/fish_variables
grep -q 'Tide style: Classic, True color' /tmp/tide.log || fail "the Tide Classic style did not apply"
grep -q '^SETUVAR tide_pwd_bg_color:303030$' "${vars}" || fail "Tide is not on the Classic style"
run tide rainbow-16color | tee /tmp/tide2.log
grep -q '^SETUVAR tide_pwd_bg_color:blue$' "${vars}" || fail "Tide is not on the Rainbow (16 colors) style"

# A distro user with a pre-existing minimal ~/.zshrc (no oh-my-zsh.sh line yet)
# still gets Oh My Zsh and ZSH_THEME wired up while keeping custom lines.
printf '# custom user alias\nalias ll="ls -la"\n' > /home/ubuntu/.zshrc
chown ubuntu: /home/ubuntu/.zshrc
run spaceship single-line "" "SPACESHIP_PROMPT_SEPARATE_LINE=false" | tee /tmp/minimal-zshrc.log
grep -q 'source "\$ZSH/oh-my-zsh.sh"' /home/ubuntu/.zshrc || fail "minimal ~/.zshrc did not get oh-my-zsh.sh sourced"
grep -q '^ZSH_THEME="spaceship"' /home/ubuntu/.zshrc || fail "minimal ~/.zshrc did not get ZSH_THEME=spaceship"
grep -q 'alias ll="ls -la"' /home/ubuntu/.zshrc || fail "minimal ~/.zshrc lost existing user content"
run spaceship single-line "" "SPACESHIP_PROMPT_SEPARATE_LINE=false" | tee /tmp/minimal-zshrc-2.log
grep -q "already up to date" /tmp/minimal-zshrc-2.log || fail "minimal ~/.zshrc was not idempotent on second run"

echo "WSL setup script passed."
