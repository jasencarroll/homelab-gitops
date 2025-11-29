# 🐆 Panther Dotfiles

Terminal cockpit for a headless Ubuntu Server laptop node.

## What's Inside

| File | Purpose |
|------|---------|
| `setup.sh` | One-shot install script |
| `.zshrc` | Zsh config with oh-my-zsh, aliases, functions |
| `.tmux.conf` | Tmux with vim keys, Tokyo Night theme, quick layouts |
| `.nanorc` | Nano with syntax highlighting, modern keybinds |
| `starship.toml` | Fast, pretty prompt with k8s/git context |
| `btop.conf` | System monitor theme |

## Quick Start

```bash
git clone https://github.com/jasencdev/panther-dotfiles.git
cd panther-dotfiles
chmod +x setup.sh
./setup.sh
# Reboot
```

## Tools Installed

### Core
- `zsh` + `oh-my-zsh` - Shell
- `tmux` - Terminal multiplexer
- `starship` - Prompt
- `neofetch` - System info

### Modern CLI
- `bat` - Better `cat`
- `eza` - Better `ls`
- `btop` - Better `htop`
- `fzf` - Fuzzy finder
- `ripgrep` - Better `grep`
- `fd` - Better `find`

### Cluster Management
- `k9s` - Kubernetes TUI
- `lazydocker` - Docker TUI
- `kubectl` - (install separately)

## Key Bindings

### Tmux (prefix: Ctrl+a)
| Key | Action |
|-----|--------|
| `\|` | Split vertical |
| `-` | Split horizontal |
| `h/j/k/l` | Navigate panes |
| `H/J/K/L` | Resize panes |
| `Alt+1-5` | Switch windows |
| `D` | Cockpit layout (k9s + btop + shell) |
| `M` | Monitor (btop fullscreen) |
| `r` | Reload config |

### Nano
| Key | Action |
|-----|--------|
| `Ctrl+S` | Save |
| `Ctrl+Q` | Quit |
| `Ctrl+F` | Find |
| `Ctrl+G` | Go to line |
| `Ctrl+Z` | Undo |

## Custom Functions

```bash
# Cluster overview
cluster

# Ollama status across all GPU nodes
ollama-status
```

## Aliases

```bash
# Kubernetes
k       # kubectl
kgp     # get pods
kgs     # get services
k9      # k9s

# Docker
d       # docker
dc      # docker compose
ld      # lazydocker

# Modern CLI
cat     # bat
ls      # eza
ll      # eza -la
top     # btop
```

## Theme

Tokyo Night everywhere:
- Tmux status bar
- Starship prompt
- btop colors
- fzf colors
- Nano syntax highlighting

## Node Context

This dotfiles setup is designed for **panther** - a docked XPS laptop serving as:
- Kubernetes agent node
- Embeddings inference (3050 Ti / 4GB VRAM)
- Mobile terminal when undocked

Part of the Axiom Layer cluster:
```
neko      - control plane
neko2     - control plane  
bobcat    - agent (RPi)
siberian  - GPU node (5070 Ti)
chartreux - GPU node (3080)
panther   - GPU node (3050 Ti) ← you are here
```
