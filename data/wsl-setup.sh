#!/bin/bash
# WinTool shell setup inside WSL. Runs as root (wsl -d <distro> -u root) so
# no sudo password is needed, then does per-user work as the distro's normal
# user. Safe to run more than once on an existing distro.
set -u

say() { echo "WinTool: $*"; }

prompt="${WINTOOL_SHELL_PROMPT:-oh-my-zsh}"
style="${WINTOOL_PROMPT_STYLE:-}"
omz_theme="${WINTOOL_OMZ_THEME:-robbyrussell}"
case "${omz_theme}" in *[!A-Za-z0-9._/-]*|"") omz_theme="robbyrussell" ;; esac
case "${style}" in *[!A-Za-z0-9._-]*) style="" ;; esac
# The chosen prompt style: a config file from the Powerlevel10k repository,
# or setting lines for Spaceship and Pure. Tide styles come from the id.
style_file="${WINTOOL_STYLE_FILE:-}"
case "${style_file}" in *..*|*[!A-Za-z0-9._/-]*) style_file="" ;; esac
style_settings=""
while IFS= read -r line; do
  case "${line}" in ""|*[!A-Za-z0-9_:=.\ -]*) continue ;; esac
  style_settings="${style_settings}${line}
"
done <<EOF
${WINTOOL_STYLE_SETTINGS:-}
EOF

if [ "$(id -u)" -ne 0 ]; then
  say "this script needs root. Run: wsl -d <distro> -u root -- bash $0"
  exit 2
fi

# The Linux user that gets zsh: WinTool passes the distro's default uid.
user=""
if [ -n "${WINTOOL_UID:-}" ] && [ "${WINTOOL_UID}" != "0" ]; then
  user="$(getent passwd "${WINTOOL_UID}" | cut -d: -f1)"
fi
if [ -z "${user}" ] && [ -f /etc/wsl.conf ]; then
  user="$(sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*//p' /etc/wsl.conf | head -n 1 | tr -d '[:space:]')"
fi
if [ -z "${user}" ]; then
  user="$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)"
fi
if [ -z "${user}" ] || ! id "${user}" >/dev/null 2>&1; then
  say "no Linux user was found. Open the distro once to create your user, then run Terminal setup again."
  exit 3
fi
home="$(getent passwd "${user}" | cut -d: -f6)"
say "setting up the shell for ${user} (${home}), prompt ${prompt}"

as_user() {
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "${user}" -- env HOME="${home}" USER="${user}" LOGNAME="${user}" bash -c "$1"
  else
    su -s /bin/bash "${user}" -c "$1"
  fi
}

packages="zsh git curl ca-certificates unzip"
if [ "${prompt}" = "tide" ]; then
  packages="${packages} fish"
fi
say "installing ${packages}"
if command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get update -q || say "apt-get update failed, trying the install anyway"
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q ${packages} || say "some packages did not install"
elif command -v dnf >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  dnf install -y ${packages} || say "some packages did not install"
elif command -v pacman >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  pacman -Sy --noconfirm --needed ${packages} || say "some packages did not install"
else
  say "this distro has no apt-get, dnf, or pacman. Install ${packages} first."
fi
if ! command -v zsh >/dev/null 2>&1; then
  say "zsh is not installed, so the setup stopped."
  exit 4
fi

if [ ! -d "${home}/.oh-my-zsh" ]; then
  say "installing Oh My Zsh"
  as_user 'cd "$HOME" && RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' || say "Oh My Zsh did not install"
fi

zsh_theme=""
block=""
case "${prompt}" in
  oh-my-posh)
    theme_file="${style:-jandedobbeleer}"
    case "${theme_file}" in *.omp.json) ;; *) theme_file="${theme_file}.omp.json" ;; esac
    say "installing Oh My Posh with ${theme_file}"
    as_user 'mkdir -p "$HOME/.local/bin" && curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"' || say "Oh My Posh did not install"
    as_user "mkdir -p \"\$HOME/.config/wintool\" && tmp=\"\$HOME/.config/wintool/${theme_file}.tmp\" && curl -fsSL -o \"\$tmp\" \"https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/${theme_file}\" && [ -s \"\$tmp\" ] && mv -f \"\$tmp\" \"\$HOME/.config/wintool/${theme_file}\" || { rm -f \"\$tmp\"; false; }" || say "the theme did not download, Oh My Posh will use its default"
    block="export PATH=\"\$HOME/.local/bin:\$PATH\"
if command -v oh-my-posh >/dev/null 2>&1; then
  if [ -f \"\$HOME/.config/wintool/${theme_file}\" ]; then
    eval \"\$(oh-my-posh init zsh --config \"\$HOME/.config/wintool/${theme_file}\")\"
  else
    eval \"\$(oh-my-posh init zsh)\"
  fi
fi"
    ;;
  starship)
    say "installing Starship"
    as_user 'mkdir -p "$HOME/.local/bin" && curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"' || say "Starship did not install"
    block="export PATH=\"\$HOME/.local/bin:\$PATH\"
if command -v starship >/dev/null 2>&1; then
  eval \"\$(starship init zsh)\"
fi"
    ;;
  powerlevel10k)
    say "installing Powerlevel10k"
    as_user 'd="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"; [ -d "$d" ] || git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$d"' || say "Powerlevel10k did not install"
    zsh_theme="powerlevel10k/powerlevel10k"
    [ -n "${style_file}" ] || style_file="config/p10k-${style:-lean}.zsh"
    p10k_source="${home}/.oh-my-zsh/custom/themes/powerlevel10k/${style_file}"
    if [ -f "${p10k_source}" ]; then
      if [ -f "${home}/.p10k.zsh" ] && ! cmp -s "${p10k_source}" "${home}/.p10k.zsh"; then
        cp -p "${home}/.p10k.zsh" "${home}/.p10k.zsh.wintool-$(date +%Y%m%d-%H%M%S).bak"
      fi
      cp "${p10k_source}" "${home}/.p10k.zsh"
      chown "${user}:" "${home}/.p10k.zsh" 2>/dev/null || chown "${user}" "${home}/.p10k.zsh"
      say "Powerlevel10k style: ${style_file}"
    else
      say "the Powerlevel10k style ${style_file} was not found, the setup wizard will ask on first start"
    fi
    block="POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
[[ ! -f \"\$HOME/.p10k.zsh\" ]] || source \"\$HOME/.p10k.zsh\""
    ;;
  pure)
    say "installing Pure"
    as_user 'mkdir -p "$HOME/.zsh"; [ -d "$HOME/.zsh/pure" ] || git clone --depth=1 https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"' || say "Pure did not install"
    zsh_theme=""
    block="if [ -d \"\$HOME/.zsh/pure\" ]; then
  fpath+=(\"\$HOME/.zsh/pure\")
${style_settings}  autoload -U promptinit; promptinit
  prompt pure
fi"
    ;;
  spaceship)
    say "installing Spaceship"
    as_user 'd="$HOME/.oh-my-zsh/custom/themes/spaceship-prompt"; [ -d "$d" ] || git clone --depth=1 https://github.com/spaceship-prompt/spaceship-prompt.git "$d"; ln -sfn "$d/spaceship.zsh-theme" "$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme"' || say "Spaceship did not install"
    zsh_theme="spaceship"
    block="${style_settings%
}"
    ;;
  tide)
    say "installing Tide for Fish"
    as_user "fish -lc 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; fisher install jorgebucaran/fisher; fisher install IlanCosman/tide@v6'" || say "Tide still needs a Fish login to finish"
    # Apply the chosen style the official way: "tide configure --auto" with
    # every answer given, so no question is asked.
    tide_base="${style:-lean}"
    tide_colors="True color"
    case "${tide_base}" in *-16color) tide_base="${tide_base%-16color}"; tide_colors="16 colors" ;; esac
    case "${tide_base}" in
      classic) tide_style="Classic" ;;
      rainbow) tide_style="Rainbow" ;;
      *) tide_style="Lean" ;;
    esac
    tide_args="--auto --style=${tide_style} --prompt_colors='${tide_colors}' --classic_prompt_color=Dark --show_time=No --lean_prompt_height='One line' --classic_prompt_separators=Angled --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat --powerline_prompt_style='One line' --prompt_connection=Disconnected --prompt_connection_andor_frame_color=Dark --powerline_right_prompt_frame=No --prompt_spacing=Compact --icons='Few icons' --transient=No"
    if as_user "fish -c \"tide configure ${tide_args}\" </dev/null"; then
      say "Tide style: ${tide_style}, ${tide_colors}"
    else
      say "the Tide style did not apply. Run: tide configure"
    fi
    ;;
  *)
    zsh_theme="${omz_theme}"
    ;;
esac

# ~/.zshrc: Oh My Zsh's own file is kept; WinTool sets ZSH_THEME and owns one
# block between markers. A dated backup is made only when the file changes.
zshrc="${home}/.zshrc"
draft="$(mktemp)"
if [ -f "${zshrc}" ]; then
  cp "${zshrc}" "${draft}"
elif [ -f "${home}/.oh-my-zsh/templates/zshrc.zsh-template" ]; then
  cp "${home}/.oh-my-zsh/templates/zshrc.zsh-template" "${draft}"
fi
if [ -d "${home}/.oh-my-zsh" ] && ! grep -q 'oh-my-zsh\.sh' "${draft}"; then
  omz_head="$(mktemp)"
  printf 'export ZSH="$HOME/.oh-my-zsh"\nZSH_THEME="%s"\nsource "$ZSH/oh-my-zsh.sh"\n' "${zsh_theme}" > "${omz_head}"
  if [ -s "${draft}" ]; then
    printf '\n' >> "${omz_head}"
    cat "${draft}" >> "${omz_head}"
  fi
  mv -f "${omz_head}" "${draft}"
elif grep -q '^ZSH_THEME=' "${draft}"; then
  sed -i "s|^ZSH_THEME=.*|ZSH_THEME=\"${zsh_theme}\"|" "${draft}"
fi
sed -i '/^# >>> WinTool >>>$/,/^# <<< WinTool <<<$/d' "${draft}"
if [ -n "${block}" ]; then
  printf '# >>> WinTool >>>\n%s\n# <<< WinTool <<<\n' "${block}" >> "${draft}"
fi
if [ -f "${zshrc}" ] && cmp -s "${draft}" "${zshrc}"; then
  say "${zshrc} is already up to date"
  rm -f "${draft}"
else
  if [ -f "${zshrc}" ]; then
    backup="${zshrc}.wintool-$(date +%Y%m%d-%H%M%S).bak"
    cp -p "${zshrc}" "${backup}"
    say "saved a backup to ${backup}"
  fi
  cat "${draft}" > "${zshrc}"
  rm -f "${draft}"
  chown "${user}:" "${zshrc}" 2>/dev/null || chown "${user}" "${zshrc}"
  say "wrote ${zshrc}"
fi

login_shell="$(command -v zsh)"
if [ "${prompt}" = "tide" ] && command -v fish >/dev/null 2>&1; then
  login_shell="$(command -v fish)"
fi
grep -qx "${login_shell}" /etc/shells || echo "${login_shell}" >> /etc/shells
current="$(getent passwd "${user}" | cut -d: -f7)"
if [ "${current}" != "${login_shell}" ]; then
  if chsh -s "${login_shell}" "${user}"; then
    say "the default shell for ${user} is now ${login_shell}"
  else
    say "could not change the default shell. Run: sudo chsh -s ${login_shell} ${user}"
  fi
else
  say "the default shell for ${user} is already ${login_shell}"
fi

say "shell setup finished. Open a new Ubuntu tab to use it."
exit 0
