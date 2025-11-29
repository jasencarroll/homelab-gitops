# Panther ZSH Config
# ==================

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""  # Using starship instead

plugins=(
  git
  docker
  kubectl
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf
  history
  sudo  # ESC ESC to add sudo
)

source $ZSH/oh-my-zsh.sh

# Starship prompt
eval "$(starship init zsh)"

# History
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Modern CLI aliases
alias cat='batcat --paging=never'
alias catp='batcat'
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias lt='eza -la --icons --tree --level=2'
alias tree='eza --tree --icons'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kgaa='kubectl get all -A'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kx='kubectl exec -it'
alias kns='kubectl config set-context --current --namespace'
alias k9='k9s'

# Docker
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias ld='lazydocker'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate -10'

# System
alias ports='sudo lsof -i -P -n | grep LISTEN'
alias myip='curl -s ifconfig.me'
alias dus='du -sh * | sort -h'
alias free='free -h'
alias df='df -h'
alias top='btop'
alias htop='btop'

# Tailscale
alias ts='tailscale'
alias tss='tailscale status'

# Cluster nodes
alias ssh-neko='ssh neko'
alias ssh-neko2='ssh neko2'
alias ssh-bobcat='ssh bobcat'
alias ssh-siberian='ssh siberian'
alias ssh-chartreux='ssh chartreux'

# Quick edits
alias zshrc='nano ~/.zshrc && source ~/.zshrc'
alias tmuxrc='nano ~/.tmux.conf'

# fzf configuration
export FZF_DEFAULT_OPTS='
  --height 40%
  --layout=reverse
  --border
  --color=fg:#c0caf5,bg:#1a1b26,hl:#bb9af7
  --color=fg+:#c0caf5,bg+:#292e42,hl+:#7dcfff
  --color=info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff
  --color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a
'

# Use fd for fzf if available
if command -v fdfind &> /dev/null; then
  export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# Quick cluster overview
cluster() {
  echo "🐱 Axiom Layer Cluster Status"
  echo "=============================="
  kubectl get nodes -o wide
  echo ""
  echo "📦 Pods by namespace:"
  kubectl get pods -A --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn
}

# Quick Ollama status
ollama-status() {
  echo "🧠 Ollama Status"
  echo "================"
  echo "siberian (5070 Ti):"
  curl -s http://siberian:11434/api/tags 2>/dev/null | jq -r '.models[].name' || echo "  offline"
  echo ""
  echo "chartreux (3080):"
  curl -s http://chartreux:11434/api/tags 2>/dev/null | jq -r '.models[].name' || echo "  offline"
  echo ""
  echo "panther (3050 Ti):"
  curl -s http://localhost:11434/api/tags 2>/dev/null | jq -r '.models[].name' || echo "  offline"
}

# Neofetch on new shell (comment out if annoying)
if [[ $- == *i* ]]; then
  neofetch --ascii_distro ubuntu_small
fi
