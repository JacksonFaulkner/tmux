#!/usr/bin/env bash
# Displays all tmux + sessionx keybinds in a popup (alt-?)

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
YELLOW='\033[33m'
RESET='\033[0m'

section() { printf "\n${BOLD}${YELLOW}  %s${RESET}\n" "$1"; }
bind() { printf "  ${CYAN}%-18s${RESET} %s\n" "$1" "$2"; }

section "Panes"
bind "prefix + h/j/k/l"  "Navigate panes"
bind "prefix + |"         "Split horizontal"
bind "prefix + -"         "Split vertical"

section "Windows"
bind "prefix + c"         "New window (cwd)"
bind "prefix + C-h/C-l"   "Prev / next window"

section "Tmux"
bind "prefix + w"         "SessionX picker"
bind "prefix + r"         "Reload config"
bind "alt + ?"            "This help popup"

section "SessionX (inside picker)"
bind "enter"              "Switch / create session"
bind "alt-j / alt-k"      "Navigate down / up"
bind "ctrl-u / ctrl-d"    "Scroll preview"
bind "ctrl-r"             "Rename session"
bind "alt-bspace"         "Kill session"
bind "ctrl-w"             "Window mode"
bind "ctrl-e"             "New window from cwd"
bind "ctrl-f"             "Zoxide window"
bind "ctrl-x"             "Browse config path"
bind "ctrl-t"             "Tree mode"
bind "ctrl-b"             "Back"
bind "alt-c"              "Claude history preview"
bind "?"                  "Toggle preview"
bind "esc"                "Abort"

printf "\n${DIM}  Press any key to close${RESET}\n"
read -rsn1
