#!/usr/bin/env bash

#=============================================================================
# Script to set up new operation System. 
# Only for mac & manjaro
# please read the source before you using it
#=============================================================================

set -euo pipefail  # 添加更严格的错误检查

# 统一的颜色定义
declare -r COLOR_OFF='\033[0m'       # Text Reset
declare -r COLOR_RED='\033[0;31m'          # Red
declare -r COLOR_GREEN='\033[0;32m'        # Green
declare -r COLOR_YELLOW='\033[0;33m'       # Yellow

# 日志函数
tips() {
    local level=$1
    local message=$2
    local color=""
    case $level in
        "INFO") color=$COLOR_YELLOW; symbol="[➜]" ;;
        "SUCCESS") color=$COLOR_GREEN; symbol="[✔]" ;;
        "ERROR") color=$COLOR_RED; symbol="[✖]" ;;
    esac
    printf "${color}${symbol}${COLOR_OFF} %s\n" "$message" >&2
}

info() {
    tips "INFO" "$1"
}

ok() {
    tips "SUCCESS" "$1"
}

xx() {
    tips "ERROR" "$1"
}

# 错误处理
error_handler() {
    local line_no=$1
    local error_code=$2
    xx "Error occurred in script at line: ${line_no}, error code: ${error_code}"
    exit 1
}
trap 'error_handler ${LINENO} $?' ERR

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        xx "Command not found: $1"
        return 1
    fi
}

setup_file() {
    local src=$1
    local dst=$2

    # 参数验证
    if [ -z "$src" ] || [ -z "$dst" ]; then
        xx "Source or destination path is empty"
        return 1
    fi

    # 检查源文件是否存在
    if [ ! -e "$src" ]; then
        xx "Source file/directory does not exist: $src"
        return 1
    fi

    # 如果目标已存在，先删除
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        rm -rf "$dst"
        info "Removed existing: $dst"
    fi

    # 创建目标文件的父目录（如果不存在）
    local dst_dir
    dst_dir=$(dirname "$dst")
    if [ ! -d "$dst_dir" ]; then
        mkdir -p "$dst_dir"
        info "Created directory: $dst_dir"
    fi

    # 复制文件
    if cp -vf "$src" "$dst"; then
        ok "Successfully copied: $src -> $dst"
    else
        error "Failed to copy $src to $dst"
        return 1
    fi
}


show_steps_info() {
    local title=$1
    local line=$(printf '%*s' 78 | tr ' ' '=')
    
    echo "$line"
    echo "$title"
    echo "$line"
}

skipOrNot() {
    local step_name=${1:-"this step"}
    
    printf "${COLOR_YELLOW}Do you want to execute %s? (y/yes to continue)${COLOR_OFF} " "$step_name"
    read -r choice
    
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    
    case "$choice" in
        "yes"|"y")
            info "Executing $step_name..."
            return 0
            ;;
        *)
            info "Skipping $step_name..."
            return 1
            ;;
    esac
}

# 配置项
readonly DOTFILES="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly SYSTEM="$(uname -s)"

step_package_manager(){
    if [ "$SYSTEM" == "Darwin" ]; then
        # Mac OS 相关安装
        if ! xcode-select --print-path &> /dev/null; then
            info "Installing CommandLineTools..."
            xcode-select --install || {
                xx "Failed to install CommandLineTools"
                return 1
            }
        fi
        
        if ! command -v brew &> /dev/null; then
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                xx "Failed to install Homebrew"
                return 1
            }
        fi
    else
        # Manjaro/Arch 相关安装
        sudo cp "$DOTFILES/etc/pacman.conf" /etc/pacman.conf || {
            xx "Failed to copy pacman.conf"
            return 1
        }
        
        sudo cp "$DOTFILES/etc/mirrorlist" /etc/pacman.d/mirrorlist || {
            xx "Failed to copy mirrorlist"
            return 1
        }
        
        sudo pacman -Syyuu --noconfirm || {
            xx "Failed to update system packages"
            return 1
        }
        
        info "install base tools: base-devel git curl wget yay"
        sudo pacman -S --needed --noconfirm archlinuxcn-keyring archlinuxcn-mirrorlist-git 
        sudo pacman -S --needed --noconfirm base-devel git curl wget yay

        info "config IME(input method editor)"
        sudo pacman -S --needed --noconfirm fcitx-im fcitx-configtool fcitx-googlepinyin
        setup_file "$DOTFILES/linux/.xprofile" ~/.xprofile

        # info "checking yay (aur helper)..."
        # if test "$(command -v yay)"; then
        #     ok "yay has already installed"
        # else
        #     info "yay needs to be installed"
        #     git clone https://aur.archlinux.org/yay.git ~/tmpyay
        #     cd ~/tmpyay
        #     makepkg -si --noconfirm
        #     cd - > /dev/null 2>&1
        #     rm -rf ~/tmpyay
        #     ok "yay has installed"
        # fi

        info "update system..."
        # --ignore=fcitx-sogoupinyin
        sudo pacman -Syyuu --noconfirm 
        ok "done"
    fi
}

step_install_softwares(){
    info "prepare for package installing..."
    if [ "$SYSTEM" == "Darwin" ];then
        brew bundle -v --file="$DOTFILES"/packages/Brewfile
    else
        sudo pacman -S --needed --noconfirm $(cat "$DOTFILES/packages/pacman_pkglist"|xargs)
        yay --aururl "https://aur.tuna.tsinghua.edu.cn" --save
        yay -S --needed --noconfirm $(cat "$DOTFILES/packages/aur_pkglist"|xargs)
    fi
    ok "done"
}

step_create_working_directories(){
    info "Creating working directories..."
    readonly HOME_DIRS=(
        "$HOME/dev"
        "$HOME/dev/android/sdk"
        "$HOME/doc"
        "$HOME/mrepo"
        "$HOME/mrepo/github"
    )
        for dir in "${HOME_DIRS[@]}"; do
            mkdir -p "$dir"
            ok "Created directory: $dir"
        done
    ok "done"
}


step_config_git(){
    if type git > /dev/null 2>&1; then
        ok "git has already installed"
    else
        info  "Installing git"
        if [ "$SYSTEM" == "Darwin" ];then
            brew install git
        else
            sudo pacman -S --needed --noconfirm git
        fi
        ok "done"
    fi
    info "linking gitconfig"
    setup_file "$DOTFILES/git/.gitconfig" ~/.gitconfig
    info "linking git_commit_template"
    setup_file "$DOTFILES/git/git_commit_template.txt" ~/.git_commit_template.txt
    info "linking global_gitignore"
    setup_file "$DOTFILES/git/.global_gitignore" ~/.global_gitignore
    info "linking sub folder gitconfig"
    setup_file "$DOTFILES/mrepo/github/.gitconfig" ~/mrepo/github/.gitconfig
    ok "done"
}


step_config_terminal(){
    if [ "$(uname -s)" = "Darwin" ]; then
        info "config env..."
        brew install zsh antigen
        brew install iterm2
        BREW_ZSH=/usr/local/bin/zsh
        echo "zsh version: $($BREW_ZSH --version)"
        if [[ $SHELL == *"zsh"* ]]; then
            ok "Shell already set to zsh.";
        else
            info "Setting shell to zsh...";
            sudo sh -c "echo $BREW_ZSH >> /etc/shells"
            chsh -s $BREW_ZSH
            ok "default shell has set to $BREW_ZSH"
        fi

        info "config iterm2..."
        setup_file "$DOTFILES/iterm2/Snazzy.itermcolors" ~/.config/iterm2/Snazzy.itermcolors
        setup_file "$DOTFILES/iterm2/com.googlecode.iterm2.plist" ~/.config/iterm2/com.googlecode.iterm2.plist  
        # Specify the preferences directory
        defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "~/.config/iterm2"
        # Tell iTerm2 to use the custom preferences in the directory
        defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true
        ok "done iterm2 config"
        echo "you may need to open iterm2, and set it as the default terminal."
        info "linking zshrc"
        setup_file "$DOTFILES/zsh/.zshrcDarwin" ~/.zshrc
    else
        info "config env..."
        sudo pacman -S --needed --noconfirm zsh terminator
        yay -S --needed --noconfirm antigen-git

        MY_ZSH=/usr/bin/zsh
        echo "zsh version: $($MY_ZSH --version)"
        if [[ $SHELL == *"zsh"* ]]; then
            ok "Shell already set to zsh.";
        else
            info "Setting shell to zsh...";
            chsh -s $MY_ZSH
            ok "default shell has set to $MY_ZSH"
        fi

        info "config terminator"
        sudo pacman -S --needed --noconfirm terminator 
        mkdir -p ~/.config/terminator/
        setup_file "$DOTFILES/terminator/config" ~/.config/terminator/config
        ok "done terminator config"
        info "linking zshrc"
        setup_file "$DOTFILES/zsh/.zshrcPacman" ~/.zshrc
    fi
    ok "done"
}


step_config_vim(){
    info "link config files"
    setup_file "$DOTFILES/vim/complete.vimrc" ~/.vimrc
    ok "done"
    info "install vim-plug"
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    ok "done"
    info "install/update vim plugin"
    vim +'PlugInstall --sync' +qa
    vim +'PlugUpdate' +qa
    ok "done"
}


step_config_vscode(){
    if type code > /dev/null 2>&1; then
        ok "vscode has already installed"
    else
        info  "Installing vscode"
        if [ "$SYSTEM" == "Darwin" ];then
            brew install visual-studio-code
        else
            sudo pacman -S --noconfirm visual-studio-code 
        fi
        ok "vscode has installed"
    fi
    if test "$(command -v code)"; then
        # from `code --list-extensions`
        # code --list-extensions | xargs -L 1 echo code --install-extension
        info "update vscode plugins"
        echo "yes" | code --install-extension k--kato.intellij-idea-keybindings
        echo "yes" | code --install-extension zhuangtongfa.material-theme
        echo "yes" | code --install-extension vscode-icons-team.vscode-icons
        echo "yes" | code --install-extension yzhang.markdown-all-in-one
        echo "yes" | code --install-extension eamodio.gitlens
        ok "vscode plugins has updated"

        if [ "$(uname -s)" = "Darwin" ]; then
            VSCODE_HOME="$HOME/Library/Application Support/Code"
        else
            VSCODE_HOME="$HOME/.config/Code"
        fi
        info "link config files"
        setup_file "$DOTFILES/vscode/settings.json" "$VSCODE_HOME/User/settings.json"
        setup_file "$DOTFILES/vscode/keybindings.json" "$VSCODE_HOME/User/keybindings.json"
        ok "done"
    else
        echo "you may need to export code command to your shell env"
    fi
}


# 主函数
main() {

cat << "EOF"

╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║   d8888b.  .d88b.  d888888b d88888b d888888b db      d88888b .d8888.   ║
║   88  `8D .8P  Y8. `~~88~~' 88'       `88'   88      88'     88'  YP   ║
║   88   88 88    88    88    88ooo      88    88      88ooooo `8bo.     ║
║   88   88 88    88    88    88~~~      88    88      88~~~~~   `Y8b.   ║
║   88  .8D `8b  d8'    88    88        .88.   88booo. 88.     db   8D   ║
║   Y8888D'  `Y88P'     YP    YP      Y888888P Y88888P Y88888P `8888Y'   ║
║                                                                        ║
║          WARNING: Please read the source before using it!              ║
╚════════════════════════════════════════════════════════════════════════╝

EOF

    # 确认继续
    echo "current dotfiles path: $DOTFILES"
    read -r -p "Continue? [y|N] " response
    if [[ ! $response =~ ^[Yy]$ ]]; then
        xx "Setup aborted by user"
        exit 1
    fi

    # 请求管理员权限
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    show_steps_info "homebrew & pacman"
    step_package_manager

    show_steps_info "install softwares"
    if skipOrNot; then
        step_install_softwares
    else
        info "step_install_softwares skipped"
    fi

    show_steps_info "update working directories"
    step_create_working_directories

    show_steps_info "config git"
    step_config_git

    show_steps_info "terminal zsh antigen iterm2"
    step_config_terminal

    show_steps_info "config vim with vim-plug"
    step_config_vim

    show_steps_info "vscode"
     if skipOrNot; then
        step_config_vscode
    else
        info "step_config_vscode skipped"
    fi
    
cat << "EOF"

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║                     *** Congratulations! All Done! ***                    ║
║                                                                           ║
║                     Your computer are ready to use                        ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

EOF
}

main "$@"
