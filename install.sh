#!/usr/bin/env bash

# GitHub Codespaces dotfiles installation script
# This script is automatically run when creating a new Codespace

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

# Detect if running in Codespaces
if [ -n "${CODESPACES:-}" ]; then
  log "Running in GitHub Codespaces environment"
else
  log "Running in local environment"
fi

# Install system dependencies
install_dependencies() {
  log "Installing system dependencies..."

  # Update package list
  sudo apt-get update -qq

  # Install essential tools
  sudo apt-get install -y -qq \
    stow \
    zsh \
    tmux \
    fzf \
    ripgrep \
    fd-find \
    curl \
    git \
    build-essential \
    python3-pip \
    golang-go \
    postgresql-client \
    pkg-config \
    libssl-dev

  # Install Starship prompt
  if ! command -v starship &>/dev/null; then
    log "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  # Install Homebrew
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null

    # Add Homebrew to PATH for current session
    if [ -d "/home/linuxbrew/.linuxbrew" ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
  fi

  # Install Nushell
  if ! command -v nu &>/dev/null; then
    log "Installing Nushell..."
    if command -v brew &>/dev/null; then
      brew install nushell
    else
      # Fallback to cargo if brew is not available
      if command -v cargo &>/dev/null; then
        cargo install nu
      else
        warning "Could not install Nushell - neither Homebrew nor Cargo is available"
      fi
    fi
  fi

  # Install Zellij
  if ! command -v zellij &>/dev/null; then
    log "Installing Zellij..."
    if command -v brew &>/dev/null; then
      brew install zellij
    else
      # Install via official script
      bash <(curl -L zellij.dev/launch)
    fi
  fi

  # Install Neovim (latest stable)
  if ! command -v nvim &>/dev/null || [[ $(nvim --version | head -n1 | grep -oE '[0-9]+\.[0-9]+') < "0.9" ]]; then
    log "Installing Neovim..."

    # Try Homebrew first if available
    if command -v brew &>/dev/null; then
      log "Installing Neovim with Homebrew..."
      if brew install neovim; then
        log "Neovim installed successfully with Homebrew"
      else
        warning "Failed to install Neovim with Homebrew, trying other methods..."

        # For Ubuntu/Debian systems, use apt repository
        if command -v apt-get &>/dev/null; then
          # Try to install from default repos first
          if ! sudo apt-get install -y -qq neovim; then
            # If that fails or version is too old, use PPA
            log "Installing Neovim from PPA..."
            sudo apt-get install -y -qq software-properties-common
            sudo add-apt-repository -y ppa:neovim-ppa/stable
            sudo apt-get update -qq
            sudo apt-get install -y -qq neovim
          fi
        else
          # Fallback to downloading binary
          log "Installing Neovim from binary..."
          NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -oP '"tag_name": "\K[^"]+')
          curl -LO "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux64.tar.gz"
          sudo tar -C /opt -xzf nvim-linux64.tar.gz
          sudo ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
          rm nvim-linux64.tar.gz
        fi
      fi
    # If no Homebrew, try apt
    elif command -v apt-get &>/dev/null; then
      # Try to install from default repos first
      if ! sudo apt-get install -y -qq neovim; then
        # If that fails or version is too old, use PPA
        log "Installing Neovim from PPA..."
        sudo apt-get install -y -qq software-properties-common
        sudo add-apt-repository -y ppa:neovim-ppa/stable
        sudo apt-get update -qq
        sudo apt-get install -y -qq neovim
      fi
    else
      # Fallback to downloading binary for non-apt systems
      log "Installing Neovim from binary..."
      NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -oP '"tag_name": "\K[^"]+')
      curl -LO "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux64.tar.gz"
      sudo tar -C /opt -xzf nvim-linux64.tar.gz
      sudo ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
      rm nvim-linux64.tar.gz
    fi
  fi
}

# Setup dotfiles with stow
setup_dotfiles() {
  log "Setting up dotfiles with GNU Stow..."

  # Get the directory where this script is located
  DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$DOTFILES_DIR"

  # Define packages to install
  # Terminal emulators are excluded in Codespaces
  if [ -n "${CODESPACES:-}" ]; then
    PACKAGES=(nvim tmux zshrc starship)
  else
    PACKAGES=(nvim tmux zshrc starship alacritty kitty ghostty)
  fi

  # Add zellij if directory exists
  if [ -d "zellij" ]; then
    PACKAGES+=(zellij)
  fi

  # Backup existing configs if they exist
  for package in "${PACKAGES[@]}"; do
    if [ -d "$package" ]; then
      log "Processing $package..."

      # Find all files that would be stowed
      while IFS= read -r -d '' file; do
        # Convert package path to home path
        home_file="${file#$package/}"
        home_path="$HOME/$home_file"

        # If file exists and is not a symlink, back it up
        if [ -e "$home_path" ] && [ ! -L "$home_path" ]; then
          warning "Backing up existing $home_path to $home_path.backup"
          mv "$home_path" "$home_path.backup"
        fi
      done < <(find "$package" -type f -print0)
    fi
  done

  # Stow all packages
  for package in "${PACKAGES[@]}"; do
    if [ -d "$package" ]; then
      log "Stowing $package..."
      stow -v -t "$HOME" "$package" || {
        error "Failed to stow $package"
        warning "You may need to resolve conflicts manually"
      }
    else
      warning "Package $package not found, skipping..."
    fi
  done
}

# Configure development environment
configure_environment() {
  log "Configuring development environment..."

  # Set zsh as default shell if not already
  if [ "$SHELL" != "$(which zsh)" ]; then
    if [ -n "${CODESPACES:-}" ]; then
      warning "Cannot change default shell in Codespaces, but zsh is available"
    else
      log "Setting zsh as default shell..."
      sudo chsh -s "$(which zsh)" "$USER"
    fi
  fi

  # Install Tmux Plugin Manager
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    log "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi

  # Create necessary directories
  mkdir -p "$HOME/.config"
  mkdir -p "$HOME/.local/share/nvim"
  mkdir -p "$HOME/.cache/nvim"
}

# Post-installation setup
post_install() {
  log "Running post-installation setup..."

  # Install tmux plugins
  if [ -f "$HOME/.tmux.conf" ] && [ -d "$HOME/.tmux/plugins/tpm" ]; then
    log "Installing tmux plugins..."
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" || warning "Failed to install tmux plugins"
  fi

  # Neovim will install plugins on first launch
  log "Neovim plugins will be installed on first launch"

  # Add Homebrew to PATH in shell configs if it exists
  if [ -d "/home/linuxbrew/.linuxbrew" ]; then
    # Add to bashrc for Codespaces compatibility
    if ! grep -q "linuxbrew" "$HOME/.bashrc" 2>/dev/null; then
      log "Adding Homebrew to bash PATH..."
      echo '' >> "$HOME/.bashrc"
      echo '# Homebrew' >> "$HOME/.bashrc"
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.bashrc"
    fi
    
    # Also ensure it's in zshrc
    if [ -f "$HOME/.zshrc" ] && ! grep -q "linuxbrew" "$HOME/.zshrc" 2>/dev/null; then
      log "Adding Homebrew to zsh PATH..."
      echo '' >> "$HOME/.zshrc"
      echo '# Homebrew' >> "$HOME/.zshrc"
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.zshrc"
    fi
  fi

  # Add Starship initialization to shells
  if command -v starship &>/dev/null; then
    # Add to bashrc
    if ! grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
      log "Adding Starship to bash..."
      echo '' >> "$HOME/.bashrc"
      echo '# Starship prompt' >> "$HOME/.bashrc"
      echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"
    fi
    
    # Add to zshrc if it doesn't already have it
    if [ -f "$HOME/.zshrc" ] && ! grep -q "starship init zsh" "$HOME/.zshrc" 2>/dev/null; then
      log "Adding Starship to zsh..."
      echo '' >> "$HOME/.zshrc"
      echo '# Starship prompt' >> "$HOME/.zshrc"
      echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
    fi
  fi

  # Source zsh configuration if in interactive shell
  if [ -n "${ZSH_VERSION:-}" ]; then
    source "$HOME/.zshrc"
  fi
}

# Main installation flow
main() {
  log "Starting dotfiles installation..."

  # Check if running with required permissions
  if [ -n "${CODESPACES:-}" ] || [ "$EUID" -eq 0 ] || groups | grep -q sudo; then
    install_dependencies
  else
    warning "Skipping system dependencies installation (no sudo access)"
    warning "Please install manually: stow, zsh, tmux, neovim, starship, fzf, ripgrep"
  fi

  setup_dotfiles
  configure_environment
  post_install

  log "Installation complete!"

  if [ -n "${CODESPACES:-}" ]; then
    log "Your Codespace is ready! Neovim plugins will install on first launch."
    log "To use zsh, run: exec zsh"
  else
    log "Please restart your terminal or run: exec zsh"
  fi
}

# Run main function
main "$@"
