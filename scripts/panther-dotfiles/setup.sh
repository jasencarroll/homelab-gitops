#!/bin/bash
# Panther dotfiles setup
# Ubuntu Server → spiffy terminal cockpit

set -e

echo "🐆 Setting up Panther..."

# Update system
sudo apt update && sudo apt upgrade -y

# Core tools
sudo apt install -y \
  zsh \
  tmux \
  git \
  curl \
  wget \
  unzip \
  htop \
  neofetch \
  ripgrep \
  fd-find \
  jq \
  tree \
  ncdu \
  nano \
  net-tools \
  dnsutils \
  ca-certificates \
  gnupg \
  lsb-release

# Modern CLI replacements
# bat (cat replacement)
sudo apt install -y bat || {
  wget -qO /tmp/bat.deb "https://github.com/sharkdp/bat/releases/download/v0.24.0/bat_0.24.0_amd64.deb"
  sudo dpkg -i /tmp/bat.deb
}

# eza (ls replacement)
sudo apt install -y eza || {
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
  sudo apt update && sudo apt install -y eza
}

# btop (htop replacement)
sudo apt install -y btop || {
  wget -qO /tmp/btop.tbz "https://github.com/aristocratos/btop/releases/latest/download/btop-x86_64-linux-musl.tbz"
  sudo tar xvjf /tmp/btop.tbz -C /usr/local/bin --strip-components=2
}

# fzf (fuzzy finder)
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --all --no-bash --no-fish

# starship prompt
curl -sS https://starship.rs/install.sh | sh -s -- -y

# oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# zsh plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# k9s (kubernetes TUI)
curl -sS https://webinstall.dev/k9s | bash

# lazydocker
curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash

# Copy dotfiles
cp .zshrc ~/.zshrc
cp .tmux.conf ~/.tmux.conf
cp .nanorc ~/.nanorc
mkdir -p ~/.config
cp starship.toml ~/.config/starship.toml
cp btop.conf ~/.config/btop/btop.conf 2>/dev/null || mkdir -p ~/.config/btop && cp btop.conf ~/.config/btop/

# Set zsh as default shell
chsh -s $(which zsh)

# Console font for HiDPI
sudo tee /etc/default/console-setup > /dev/null <<EOF
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="Terminus"
FONTSIZE="16x32"
EOF
sudo update-initramfs -u

# Lid close behavior
sudo sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf

echo ""
echo "🐆 Panther is ready."
echo "   Reboot and enjoy your cockpit."
echo ""
neofetch
