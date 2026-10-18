# Zerknięcie wyspy po długiej komendzie w terminalu: ✓ albo ✗, komenda i czas.
#
# W ~/.zshrc:
#   source ~/PluProjects/PluDynamicIslandQuickshell/integrations/island.zsh
#
# Wyłączenie po stronie wyspy: "glances.commandDone" w config.jsonc.

# Próg w sekundach — krótsze komendy nie dają zerknięcia. Ustaw przed `source`.
: ${ISLAND_CMD_MIN:=10}

# Komendy interaktywne: ich koniec to Twój własny ruch, nie wiadomość.
# Porównywane z pierwszym słowem (po sudo / env / time / nohup).
(( ${+ISLAND_CMD_IGNORE} )) || typeset -ga ISLAND_CMD_IGNORE=(
    vim nvim vi nano micro hx emacs less more man ssh mosh htop btop top
    watch tail journalctl claude qs tmux screen python python3 ipython node
    lazygit fzf yazi ranger mc
)

# Katalog projektu z położenia tego pliku — qs szuka instancji po ścieżce.
typeset -g _island_dir=${${(%):-%x}:A:h:h}

zmodload zsh/datetime
autoload -Uz add-zsh-hook

typeset -g _island_cmd=""
typeset -g _island_start=0

_island_preexec() {
    _island_cmd=$1
    _island_start=$EPOCHSECONDS
}

_island_precmd() {
    local code=$?
    (( _island_start )) || return
    local secs=$(( EPOCHSECONDS - _island_start ))
    local cmd=$_island_cmd
    _island_start=0

    (( secs >= ISLAND_CMD_MIN )) || return
    # Ctrl+C (130) i Ctrl+Z (148): przerwałeś sam, patrzysz na terminal.
    (( code == 130 || code == 148 )) && return

    local -a words=(${(z)cmd})
    while (( $#words )) && [[ ${words[1]} == (sudo|doas|env|time|nohup|command|builtin|[A-Za-z_]*=*) ]]; do
        shift words
    done
    (( $#words )) || return
    (( ${ISLAND_CMD_IGNORE[(Ie)${words[1]:t}]} )) && return

    # Pierwsza linia, przycięta — wyspa i tak obcina, a argv nie musi nieść całego skryptu.
    cmd=${${cmd%%$'\n'*}[1,80]}

    # W tle i odpięte: prompt nie czeka na qs, a brak działającej wyspy nic nie psuje.
    qs -p $_island_dir ipc call island commandDone "$cmd" $code $secs &>/dev/null &!
}

add-zsh-hook preexec _island_preexec
add-zsh-hook precmd _island_precmd
