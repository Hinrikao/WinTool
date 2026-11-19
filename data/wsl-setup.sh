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

case "${WINTOOL_SHELL_PROMPT:-}" in
  powerlevel10k)
    echo "WinTool: installing Powerlevel10k"
    theme_dir="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
    if [ ! -d "${theme_dir}" ]; then
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${theme_dir}"
    fi
    if [ -f "${HOME}/.zshrc" ]; then
      sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "${HOME}/.zshrc" || true
    fi
    ;;
  pure)
    echo "WinTool: installing Pure"
    mkdir -p "${HOME}/.zsh"
    if [ ! -d "${HOME}/.zsh/pure" ]; then
      git clone --depth=1 https://github.com/sindresorhus/pure.git "${HOME}/.zsh/pure"
    fi
    touch "${HOME}/.zshrc"
    grep -q 'pure.zsh' "${HOME}/.zshrc" || printf '\nfpath+=%s\nautoload -U promptinit; promptinit\nprompt pure\n' "${HOME}/.zsh/pure" >> "${HOME}/.zshrc"
    ;;
  spaceship)
    echo "WinTool: installing Spaceship"
    theme_dir="${HOME}/.oh-my-zsh/custom/themes/spaceship-prompt"
    if [ ! -d "${theme_dir}" ]; then
      git clone --depth=1 https://github.com/spaceship-prompt/spaceship-prompt.git "${theme_dir}"
      ln -sfn "${theme_dir}/spaceship.zsh-theme" "${HOME}/.oh-my-zsh/custom/themes/spaceship.zsh-theme"
    fi
    if [ -f "${HOME}/.zshrc" ]; then
      sed -i 's/^ZSH_THEME=.*/ZSH_THEME="spaceship"/' "${HOME}/.zshrc" || true
    fi
    ;;
  oh-my-zsh)
    theme="${WINTOOL_OMZ_THEME:-robbyrussell}"
    echo "WinTool: setting Oh My Zsh theme to ${theme}"
    if [ -f "${HOME}/.zshrc" ]; then
      sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"${theme}\"/" "${HOME}/.zshrc" || true
    fi
    ;;
  tide)
    echo "WinTool: installing Fish and Tide"
    if command -v apt-get >/dev/null 2>&1; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fish
    fi
    fish -lc 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; fisher install jorgebucaran/fisher; fisher install IlanCosman/tide@v6' || echo "WinTool: Tide still needs a Fish login to finish."
    ;;
esac

echo "WinTool: zsh setup finished"
