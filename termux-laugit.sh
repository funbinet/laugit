#!/bin/bash
set -euo pipefail

RED="\x1b[31m"; GREEN="\x1b[32m"; YELLOW="\x1b[33m"; CYAN="\x1b[36m"; BLUE="\x1b[34m"; MAGENTA="\x1b[35m"; RESET="\x1b[0m"

TOOLNAME="laugit"
CONFIG_DIR="$PWD/.config/laugit"
STATE_DIR="$PWD/.local/state/laugit"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.json"
LOGS_DIR="$STATE_DIR/logs"
LOG_FILE="$LOGS_DIR/laugit.log"

mkdir -p "$CONFIG_DIR" "$LOGS_DIR"

GITHUB_USERNAME=""
GITHUB_TOKEN=""

get_timestamp() { printf "%s" "$(date '+%Y-%m-%d %H:%M:%S')"; }

pause() {
    if [[ -t 1 ]]; then
        read -rp "$(printf "\n${GREEN}[${TOOLNAME}]::[Next]:${RESET} Press Enter to continue ${YELLOW}${RESET}\n\n")" _
    fi
}
banner() {
    local NOW
    NOW=$(get_timestamp)
    printf "${RED}  ╔═════════════════════════╗${RESET}"
    printf "\n${RED}  ║${RESET}${GREEN}       L Λ U G I T       ${RESET}${RED}║${RESET}"
    printf "\n${RED}  ║  Git Terminal Automata  ║${RESET}"
    printf "\n${RED}  ║     Author: ${RESET}${GREEN}Funbin💀${RESET}${RED}    ║${RESET}"
    printf "\n${RED}  ╚═════════════════════════╝${RESET}"
    
    printf "\n${GREEN}  [%s]:[EAT]${RESET}\n\n" "$NOW"
}

banner
get_repo_root() {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        git rev-parse --show-toplevel
    else
        printf ""
    fi
}

_log() {
    mkdir -p "$LOGS_DIR"
    local LOG_SIZE=0
    if [[ -f "$LOG_FILE" ]]; then
        LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    if [ "$LOG_SIZE" -gt 500000 ]; then
        for i in 4 3 2 1; do
            [ -f "$LOGS_DIR/laugit.log.$i" ] && mv "$LOGS_DIR/laugit.log.$i" "$LOGS_DIR/laugit.log.$((i+1))"
        done
        mv "$LOG_FILE" "$LOGS_DIR/laugit.log.1"
        printf "\n${YELLOW}[!]::[Log File Rotated]${RESET}\n"
    fi
    printf "[%s] %s\n" "$(get_timestamp)" "$1" >> "$LOG_FILE"
}

_git_exec() {
    local command_name="$1"; shift
    local cmd_repr
    cmd_repr=$(printf '%q ' "$@")
    
    printf "\n${YELLOW} [+] Executing: git %s${RESET}\n" "$cmd_repr"
    _log "EXEC: git ${cmd_repr}"
    
    local output
    set +e
    output=$(git "$@" 2>&1)
    local status=$?
    set -e

    local sanitized_output
    sanitized_output=$(sed -E -e 's#(https://)[^@/]+@#\1***@#g' -e 's#(git@)[^:]+:#\1***:#g' <<<"$output")

    if [ $status -eq 0 ]; then
        printf "\n${GREEN}[ %s ]${RESET}\n" "$command_name"
        if [ -n "$sanitized_output" ]; then
            printf "\n"
            printf "%s\n" "$sanitized_output" | awk -v GREEN="${GREEN}" -v RESET="${RESET}" '{print GREEN " " $0 RESET}'
        fi
        _log "SUCCESS: $command_name"
        return 0
    else
        printf "\n${RED}[✖] %s Failed!${RESET}\n" "$command_name"
        printf "\n"
        printf "%s\n" "$sanitized_output" | awk -v RED="${RED}" -v RESET="${RESET}" '{print RED " " $0 RESET}'
        _log "FAIL: $command_name - $output"
        return "$status"
    fi
}

check_repo_exists() {
    set +e
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        set -e
        printf "\n${RED}[!] Not a Git repository.${RESET}\n"
        if [ "$1" == "interactive" ]; then
            pause
        fi
        return 1
    fi
    set -e
    return 0
}

check_internet() {
    printf "\n${CYAN}[?]:[Internet Connection Check.]${RESET}\n"
    if ! curl -Is https://github.com --connect-timeout 3 --max-time 5 >/dev/null 2>&1; then
        printf "${RED}[!]::[No Internet Connectivity.]${RESET}\n\n"
        return 1
    fi
        printf "${GREEN}[✔]::[Internet Connection Good.]${RESET}\n\n"
    return 0
}

check_dependencies() {
    DEPS=("git" "jq" "sed" "less" "curl")
    
    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            printf "\n${CYAN}[?]::[Checking Dependencies]${RESET}\n"
            printf "\n${RED}[!]::[%s] Not Found — Installing Now${RESET}\n" "$dep"
            if command -v apt &>/dev/null; then
                sudo apt install -y "$dep" &>/dev/null && printf "${GREEN}[✔]::[%s] Installed${RESET}\n" "$dep" || { printf "${RED}[✖]::[%s] Installation Failed. Aborting.${RESET}\n" "$dep"; exit 1; }
            elif command -v yum &>/dev/null; then
                sudo yum install -y "$dep" &>/dev/null && printf "${GREEN}[✔]::[%s] Installed${RESET}\n" "$dep" || { printf "${RED}[✖]::[%s] Installation Failed. Aborting.${RESET}\n" "$dep"; exit 1; }
            else
                printf "\n${RED}[✖] Please install %s manually.${RESET}\n" "$dep"; exit 1
            fi
        fi
    done
}

load_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        if ! jq -e . "$CREDENTIALS_FILE" >/dev/null 2>&1; then
             printf "\n${RED}[✖] Credentials JSON is corrupted or invalid.${RESET}\n"
             rm -f "$CREDENTIALS_FILE"
             return 1
        fi
        GITHUB_USERNAME=$(jq -r '.username' "$CREDENTIALS_FILE" 2>/dev/null)
        GITHUB_TOKEN=$(jq -r '.token' "$CREDENTIALS_FILE" 2>/dev/null)
        _log "Credentials loaded."
    else
        _log "Credentials file not found."
    fi
}

check_or_get_user_info() {
    local name
    local email
    set +e
    name=$(git config user.name)
    email=$(git config user.email)
    set -e

    if [ -z "$name" ] || [ -z "$email" ]; then
        printf "\n${YELLOW}[!]::[Git User Info Missing]${RESET}\n"
        
        printf "${BLUE}[${TOOLNAME}]::[Your Git Name]:${RESET} "
        read -r user_name
        printf "\n${BLUE}[${TOOLNAME}]::[Your Git Email]:${RESET} "
        read -r user_email
        
        _git_exec "Config Name" config --global user.name "$user_name"
        _git_exec "Config Email" config --global user.email "$user_email"
    else
        printf "\n${RED}      [ U S E R ]${RESET}\n"
        printf "\n${GREEN}    [USERS]: ${RESET}${YELLOW}$name${RESET}"
        printf "\n${GREEN}    [EMAIL]: ${RESET}${YELLOW}$email${RESET}\n\n"
    fi
}

verify_credentials() {
    if ! check_internet; then return 1; fi
    
    printf "\n${CYAN}[?]::[Verifying GitHub Token via API]${RESET}\n"
    local resp http_code body
    
    set +e
    resp=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user)
    set -e
    
    http_code="${resp: -3}"
    body="${resp:: -3}"

    if [ "$http_code" -eq 200 ] && printf '%s' "$body" | jq -e '.login' >/dev/null 2>&1; then
        printf "${GREEN}[✔]::[Token Verified for user: %s]${RESET}\n" "$(printf "%s" "$body" | jq -r '.login')"
        return 0
    else
        printf "${RED}[✖]::[Token Verification Failed (HTTP %s)]${RESET}\n" "$http_code"
        if [ "$http_code" -eq 401 ]; then
            printf "${RED}[!]::[Reason]: Token is invalid${RESET}\n"
        elif [ "$http_code" -eq 403 ]; then
            printf "${RED}[!]::[Reason]: Forbidden Token${RESET}\n"
        fi
        _log "Verification failed: HTTP $http_code. Response: $body"
        return 1
    fi
}

add_credentials() {
    printf "\n${RED}    [ ADD CREDS ]${RESET}\n\n"
    
    printf "${BLUE}  [GitHub Username]:${RESET} "
    read -r user
    printf "${BLUE}  [GitHub Token[PAT]:${RESET} "
    read -rs token
    printf "\n"
    
    GITHUB_USERNAME="$user"
    GITHUB_TOKEN="$token"

    if verify_credentials; then
        jq -n --arg user "$user" --arg tok "$token" '{username: $user, token: $tok}' > "$CREDENTIALS_FILE"
        chmod 600 "$CREDENTIALS_FILE"
        printf "${GREEN}[✔]::[Credentials Saved]:${RESET} ${CYAN}%s${RESET}\n\n" "$CREDENTIALS_FILE"
    else
        GITHUB_USERNAME=""
        GITHUB_TOKEN=""
        printf "${RED}[!]::[Credentials NOT Saved due to verification failure]${RESET}\n\n"
    fi
    pause
}

view_credentials() {
    printf "\n${RED}    [ VIEW CREDS ]${RESET}\n\n"
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        local username
        username=$(jq -r '.username' "$CREDENTIALS_FILE" 2>/dev/null)
        local token
        token=$(jq -r '.token' "$CREDENTIALS_FILE" 2>/dev/null)
        local token_start="${token:0:8}"

        
        printf "${CYAN} [File]:${RESET} %s\n" "$CREDENTIALS_FILE"
        printf "\n${GREEN}  [Git Username]:${RESET} %s\n" "$username"
        printf "${GREEN}  [GitHub Token]:${RESET} %s******************** \n" "$token_start"
    else
        printf "${RED}[!] No credentials found${RESET}\n"
        printf "${YELLOW} [Add Credentials to save them]${RESET}\n"
    fi
    pause
}

update_remote_url_with_token() {
    load_credentials
    if check_repo_exists "cli"; then
        if [[ -n "$GITHUB_USERNAME" && -n "$GITHUB_TOKEN" ]]; then
            local current_url
            set +e
            current_url=$(git config remote.origin.url 2>/dev/null)
            set -e

            if [[ -n "$current_url" ]]; then
                local base_url
                base_url=$(echo "$current_url" | sed -E 's#^https://[^@/]+@#https://#g' | sed 's#^git@github.com:#https://github.com/#')
                
                local token_url
                token_url=$(echo "$base_url" | sed "s#https://#https://$GITHUB_USERNAME:$GITHUB_TOKEN@#")
                
                if ! grep -q "$GITHUB_USERNAME:$GITHUB_TOKEN" <<< "$current_url"; then
                        printf "\n${CYAN}[!]::[Injecting Credentials]${RESET}\n"
                    if _git_exec "Set Remote Auth" remote set-url origin "$token_url"; then
                        printf "${GREEN}[✔]::[Credentials Injected]${RESET}\n"
                    fi
                fi
            fi
        fi
    fi
}

init_and_push() {
    if ! check_internet; then pause; return; fi

    load_credentials
    printf "\n${RED}    [ LOCAL MENU ]${RESET}\n\n"
    if [[ -z "$GITHUB_USERNAME" || -z "$GITHUB_TOKEN" ]]; then
        echo -e "\n${RED}[!]::[Missing GitHub credentials]${RESET}\n"
        pause
        return
    fi

    echo -e "\n${YELLOW}  [ Create New Repository ]${RESET}\n"
    read -rp "$(echo -e ${BLUE} [${TOOLNAME}]::[Enter path to your Repo]:${RESET} )" folder
    
    if [[ -z "$folder" ]]; then
        echo -e "\n${RED}[!] Repo path cannot be empty${RESET}\n"
        pause
        return
    fi

    mkdir -p "$folder"
    if ! cd "$folder"; then
        echo -e "\n${RED}[!] Failed to change directory to %s${RESET}\n" "$folder"
        pause
        return
    fi

    echo -e "\n${GREEN}  [ Initializing Repo ]${RESET}\n"
    _git_exec "Init" init
    _git_exec "Add All" add .
    printf "\n"
    read -rp "$(echo -e ${BLUE}[${TOOLNAME}]::[Enter Commit Description]:${RESET} )" commit_msg
    _git_exec "Commit" commit -m "${commit_msg:-Initial commit via script}"

    echo -e "\n${CYAN}    [ INSTRUCTIONS ]${RESET}\n"
    echo -e "${YELLOW} [1] Go to https://github.com/new and create a new repository.${RESET}"
    echo -e "${YELLOW} [2] Copy its HTTPS URL and paste it below.${RESET}\n"

    read -rp "$(echo -e ${BLUE}[${TOOLNAME}]::[Paste Repo Link]:${RESET} )" remote_url
    
    if [[ -z "$remote_url" ]]; then
        echo -e "\n${RED}[!] Repo link cannot be empty.${RESET}\n"
        pause
        return
    fi

    token_url=$(echo "$remote_url" | sed "s#https://#https://$GITHUB_USERNAME:$GITHUB_TOKEN@#")

    echo -e "\n${GREEN} [+] Configuring Remote and Pushing${RESET}"
    
    _git_exec "Branch Main" branch -M main
    _git_exec "Add Origin" remote add origin "$token_url"
    
    _git_exec "Pull Rebase (Initial)" pull origin main --rebase || true
    
    _git_exec "Push Force" push -u origin main --force

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}[✔] Repository Created & Pushed Successfully.${RESET}\n"
    else
        echo -e "\n${RED}[!] Push FAILED. Check your PAT/Username or the remote URL${RESET}\n"
    fi

    pause
}

clone_repo() {
    if ! check_internet; then pause; return; fi
    printf "\n${RED}  [ LOCAL SETUP ]${RESET}\n"
    printf "\n${YELLOW} [ CLONE REPO ]${RESET}\n\n"
    
    printf "${BLUE}[${TOOLNAME}]:[Enter Github  URL]:${RESET} "
    read -r url
    printf "${BLUE}[${TOOLNAME}]:[Enter Destination]: ${RESET} "
    read -r folder
    
    if [ -z "$folder" ]; then
        _git_exec "Clone" clone "$url"
    else
        _git_exec "Clone" clone "$url" "$folder"
    fi
    pause
}

git_status() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Status ]${RESET}\n\n"
    _git_exec "Status" status
    pause
}

git_add() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Add to Staging ]${RESET}\n\n"
    
    printf "${BLUE}[${TOOLNAME}]::[File/Path to add ('.' for all)]: ${RESET} "
    read -r path_to_add
    
    _git_exec "Add" add "$path_to_add"
    _git_exec "Status" status
    pause
}

git_commit() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Commit Staging ]${RESET}\n\n"
    
    set +e
    if git diff --cached --quiet; then
        set -e
        printf "\n${RED}[!] No changes staged for commit. Add first.${RESET}\n"
        pause
        return
    fi
    set -e
    
    printf "${BLUE}[${TOOLNAME}]::[Enter Commit Message]: ${RESET} "
    read -r commit_msg
    
    _git_exec "Commit" commit -m "$commit_msg"
    pause
}

# START: Git Log fix
git_log() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ History ]${RESET}\n"

    # Display oneline/graph log using _git_exec styling
    printf "\n${CYAN}[Option: Log --oneline --graph (Top 20)]${RESET}\n"
    local oneline_output
    set +e
    oneline_output=$(git log --oneline --graph --all -n 20 2>&1)
    local status=$?
    set -e
    if [ $status -eq 0 ]; then
        printf "\n"
        printf "%s\n" "$oneline_output" | awk -v GREEN="${GREEN}" -v RESET="${RESET}" '{print GREEN " " $0 RESET}'
        _log "SUCCESS: Log --oneline"
    else
        printf "\n${RED}[✖] Log --oneline Failed! Error Below.${RESET}\n"
        printf "\n"
        printf "%s\n" "$oneline_output" | awk -v RED="${RED}" -v RESET="${RESET}" '{print RED " " $0 RESET}'
        _log "FAIL: Log --oneline - $oneline_output"
    fi

    # Display full log using pager
    printf "\n${CYAN}[Option: Full Log (press Q to exit)]${RESET}\n"
    local log_output
    log_output=$(git log 2>&1)
    printf "%s\n" "$log_output" | ${PAGER:-less -R}
    pause
}
# END: Git Log fix

git_diff() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Diff Changes ]${RESET}\n\n"
    
    printf "${CYAN} [1] Unstaged Changes${RESET}\n"
    printf "${CYAN} [2] Staged    Changes${RESET}\n"
    printf "\n${RED}[X] Local Menu${RESET}\n\n"
    printf "${BLUE}[${TOOLNAME}]::[Select Diff Type]: ${RESET} "
    read -r diff_choice

    local diff_output
    local log_msg
    case $diff_choice in
        1) diff_output=$(git diff 2>&1); log_msg="EXEC: git diff" ;;
        2) diff_output=$(git diff --staged 2>&1); log_msg="EXEC: git diff --staged" ;;
        [Xx]) return ;;
        *) printf "\n${RED}[!] Invalid selection.${RESET}\n"; pause; return ;;
    esac
    printf "\n${YELLOW} [+] Executing: git diff${RESET}\n"
    _log "$log_msg"
    printf "%s\n" "$diff_output" | ${PAGER:-less -R}
    pause
}

git_undo() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Undo Changes ]${RESET}\n\n"
    
    printf "${CYAN} [1] Restore${RESET}\n"
    printf "${CYAN} [2] Unstage${RESET}\n"
    printf "${CYAN} [3] Discard${RESET}\n"
    printf "\n${RED}[X] Local Menu${RESET}\n\n"
    printf "${BLUE}[${TOOLNAME}]::[Select Undo Action]: ${RESET} "
    read -r undo_choice
    
    case $undo_choice in
        1)
            printf "${BLUE}[${TOOLNAME}]::[File to restore ('.' for all)]: ${RESET} "
            read -r file
            _git_exec "Restore" restore "$file"
            ;;
        2)
            printf "${BLUE}[${TOOLNAME}]::[File to unstage ('.' for all)]: ${RESET} "
            read -r file
            _git_exec "Unstage" reset "$file"
            ;;
        3)
            printf "${RED}[${TOOLNAME}]::[Type ${RESET}${CYAN}I-UNDERSTAND-RESET${RESET}${RED} to continue]: ${RESET} "
            read -r confirmation_hash
            
            if [[ "$confirmation_hash" == "I-UNDERSTAND-RESET" ]]; then
                printf "${RED}[?] Final confirmation to HARD RESET (yes/no): ${RESET} "
                read -r final_confirm
                if [[ "$final_confirm" == "yes" ]]; then
                    _git_exec "HARD Reset" reset --hard HEAD
                else
                    printf "${YELLOW}[!] Reset cancelled.${RESET}\n"
                fi
            elif [[ "$confirmation_hash" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
                printf "${RED}[!] Hash %s. Final confirmation (yes/no): ${RESET} " "$confirmation_hash"
                read -r final_confirm
                if [[ "$final_confirm" == "yes" ]]; then
                    _git_exec "HARD Reset" reset --hard "$confirmation_hash"
                else
                    printf "${YELLOW}[!] Reset cancelled.${RESET}\n"
                fi
            else
                printf "${RED}[!] Confirmation failed or invalid hash format.${RESET}\n"
            fi
            ;;
      [Xx]) break ;;
        *) printf "\n${RED}[!] Invalid selection.${RESET}\n" ;;
    esac
    pause
}

git_branch_list() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Branch List ]${RESET}\n\n"
    _git_exec "Branch List" branch -a
    pause
}

# START: New function to switch branch
git_branch_switch() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Switch Branch ]${RESET}\n\n"
    _git_exec "Branch List" branch -l
    printf "${BLUE}[${TOOLNAME}]::[Branch Name to Switch To]: ${RESET} "
    read -r target_branch
    
    if [ -z "$target_branch" ]; then
        printf "${RED}[!] Branch name cannot be empty.${RESET}\n"
    else
        _git_exec "Switch Branch" checkout "$target_branch"
    fi
    pause
}
# END: New function to switch branch

git_branch_create_switch() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Create & Switch Branch ]${RESET}\n\n"
    printf "${BLUE}[${TOOLNAME}]::[New Branch Name]: ${RESET} "
    read -r new_branch
    
    _git_exec "Create & Switch" checkout -b "$new_branch"
    pause
}

git_branch_merge() {
    if ! check_repo_exists "interactive"; then return; fi
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    printf "\n${YELLOW} [ Merge Branch ]${RESET}\n\n"
    printf "${MAGENTA}[Current Branch]: %s${RESET}\n" "$current_branch"
    _git_exec "Branch List" branch
    
    printf "${BLUE}[${TOOLNAME}]::[Branch to MERGE into %s]: ${RESET} " "$current_branch"
    read -r source_branch
    
    _git_exec "Merge" merge "$source_branch"
    pause
}

git_branch_rebase() {
    if ! check_repo_exists "interactive"; then return; fi
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    printf "\n${YELLOW} [ Rebase Branch ]${RESET}\n\n"
    printf "${RED}[!] WARNING: Do not rebase published commits!${RESET}\n"
    printf "\n${MAGENTA}[Current Branch]: %s${RESET}\n" "$current_branch"
    _git_exec "Branch List" branch
    
    printf "${BLUE}[${TOOLNAME}]::[Branch to rebase %s ONTO]: ${RESET} " "$current_branch"
    read -r target_branch
    
    _git_exec "Rebase" rebase "$target_branch"
    pause
}

git_branch_delete() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Delete Branch ]${RESET}\n\n"
    _git_exec "Branch List" branch
    
    printf "${BLUE}[${TOOLNAME}]::[Branch to DELETE]: ${RESET} "
    read -r branch_to_delete
    
    printf "${RED}[${TOOLNAME}]::[Delete '%s' branch Use '-D' for force delete[d/D/n]: ${RESET} " "$branch_to_delete"
    read -r confirm
    
    case $confirm in
        d) _git_exec "Delete Branch" branch -d "$branch_to_delete" ;;
        D) _git_exec "Force Delete Branch" branch -D "$branch_to_delete" ;;
        *) printf "\n${YELLOW}[!] Deletion cancelled.${RESET}\n";;
    esac
    pause
}
# START: Stash menu fix (ensuring _git_exec is used for consistency)
git_stash_menu() {
    if ! check_repo_exists "interactive"; then return; fi
    printf "\n${YELLOW} [ Stash Changes ]${RESET}\n\n"
    
    printf "${CYAN} [1] Stash${RESET}\n"
    printf "${CYAN} [2] Apply${RESET}\n"
    printf "${CYAN} [3] Pop${RESET}\n"
    printf "${CYAN} [4] List${RESET}\n"
    printf "${CYAN} [5] Drop${RESET}\n"
    printf "\n${RED}[X] Local Menu${RESET}\n\n"
    printf "${BLUE}[${TOOLNAME}]::[Select Stash Action]: ${RESET} "
    read -r stash_choice
    
    case $stash_choice in
        1)
            printf "${BLUE}[${TOOLNAME}]::[Stash Message [optional]: ${RESET} "
            read -r stash_msg
            _git_exec "Stash Save" stash push -m "${stash_msg:-Auto Stash}"
            ;;
        2)
            _git_exec "Stash List" stash list # Show list before applying
            printf "${BLUE}[${TOOLNAME}]::[Index to Apply (leave blank for latest)]: ${RESET} "
            local stash_index
            read -r stash_index
            _git_exec "Stash Apply" stash apply "$stash_index"
            ;;
        3)
            _git_exec "Stash List" stash list # Show list before popping
            printf "${BLUE}[${TOOLNAME}]::[Index to Pop (leave blank for latest)]: ${RESET} "
            local stash_index
            read -r stash_index
            _git_exec "Stash Pop" stash pop "$stash_index"
            ;;
        4)
            _git_exec "Stash List" stash list
            ;;
        5)
            _git_exec "Stash List" stash list
            printf "${BLUE}[${TOOLNAME}]::[Index to Drop [e.g.stash@{1}]: ${RESET} "
            local stash_index
            read -r stash_index
            if [[ -n "$stash_index" ]]; then
                _git_exec "Stash Drop" stash drop "$stash_index"
            else
                 printf "\n${RED}[!] Stash index is required to drop.${RESET}\n"
            fi
            ;;
      [Xx]) return ;;
        *) printf "\n${RED}[!] Invalid selection.${RESET}\n" ;;
    esac
    pause
}
# END: Stash menu fix

git_tag_menu() {
    if ! check_repo_exists "interactive"; then return; fi
    
    while true; do
        printf "\n${YELLOW} [ Tag Management ]${RESET}\n\n"
        printf "${CYAN} [1] List Tags${RESET}\n"
        printf "${CYAN} [2] Create Tag${RESET}\n"
        printf "${CYAN} [3] Delete Local Tag${RESET}\n"
        printf "${CYAN} [4] Push Tag to Remote${RESET}\n"
        printf "\n${RED} [X] Local Menu${RESET}\n\n"
        printf "${BLUE}[${TOOLNAME}]::[Select Tag Action]: ${RESET} "
        read -r tag_choice
        
        case $tag_choice in
            1)
                if ! check_internet; then pause; return; fi
                update_remote_url_with_token
                _git_exec "List Tags" tag -l
                _git_exec "List Remote Tags" ls-remote --tags origin
                ;;
            2)
                printf "${BLUE}[${TOOLNAME}]::[Tag Name (e.g., v1.0.0)]: ${RESET} "
                read -r tag_name
                printf "${BLUE}[${TOOLNAME}]::[Tag Message]: ${RESET} "
                read -r tag_msg
                _git_exec "Create Tag" tag -a "$tag_name" -m "$tag_msg"
                ;;
            3)
                _git_exec "List Tags" tag -l
                printf "${BLUE}[${TOOLNAME}]::[Tag Name to Delete Locally]: ${RESET} "
                read -r tag_name
                _git_exec "Delete Local Tag" tag -d "$tag_name"
                ;;
            4)
                if ! check_internet; then pause; return; fi
                update_remote_url_with_token
                _git_exec "List Tags" tag -l
                printf "${BLUE}[${TOOLNAME}]::[Tag Name to Push]: ${RESET} "
                read -r tag_name
                _git_exec "Push Tag" push origin "$tag_name"
                ;;
            [Xx]) break ;;
            *) printf "${RED}[!] Invalid selection.${RESET}\n" ;;
        esac
        pause
    done
}

# START: Dynamic gitignore builder fix
_build_gitignore() {
    if ! check_repo_exists "interactive"; then 
        printf "\n${RED}[!] Not a Git repository. Run 'init' first.${RESET}\n"
        pause
        return
    fi
    printf "\n${YELLOW} [ Gitignore Builder ]${RESET}\n\n"

    # Get list of files/directories (excluding hidden ones except for .gitignore itself)
    local all_files_array
    mapfile -t all_files_array < <(find . -maxdepth 1 -mindepth 1 -name .git -prune -o -print | sed 's/^\.\///')
    
    if [ ${#all_files_array[@]} -eq 0 ]; then
        printf "${YELLOW}[!] Current directory is empty. Nothing to ignore.${RESET}\n"
        pause
        return
    fi

    printf "${CYAN} [ Modes ]${RESET}\n"
    printf "${CYAN} [U] Use Mode (Select files to KEEP/TRACK - Others will be ignored)${RESET}\n"
    printf "${CYAN} [I] Ignore Mode (Select files to IGNORE - Others will be kept)${RESET}\n"
    printf "\n${RED}[X] Cancel${RESET}\n\n"
    printf "${BLUE}[${TOOLNAME}]::[Select Mode]: ${RESET} "
    read -r mode_choice

    case "$mode_choice" in
        [Uu]) local mode="use" ;;
        [Ii]) local mode="ignore" ;;
        [Xx]) printf "\n${YELLOW}[!] Cancelled .gitignore generation.${RESET}\n"; pause; return ;;
        *) printf "\n${RED}[!] Invalid mode selection. Cancelled.${RESET}\n"; pause; return ;;
    esac

    printf "\n${MAGENTA} [ Current Directory Contents ]${RESET}\n"
    local indexed_files=()
    local i=1
    for file in "${all_files_array[@]}"; do
        indexed_files[i]="$file"
        printf "  [${YELLOW}%s${RESET}] %s\n" "$i" "$file"
        i=$((i+1))
    done

    printf "\n${BLUE}[${TOOLNAME}]::[Enter file numbers to ${mode^^} (e.g., 1 3 4 or 1-3)]: ${RESET} "
    read -r choices_str

    if [ -z "$choices_str" ]; then
        printf "\n${YELLOW}[!] No files selected. Cancelled .gitignore generation.${RESET}\n"
        pause
        return
    fi

    local selected_files=()
    local selections
    IFS=' ' read -r -a selections <<< "$choices_str"
    
    # Process choices, including ranges
    for choice in "${selections[@]}"; do
        if [[ "$choice" =~ ^[0-9]+-[0-9]+$ ]]; then
            local start
            local end
            start="${choice%-*}"
            end="${choice#*-}"
            for ((j=start; j<=end; j++)); do
                if [ -n "${indexed_files[$j]}" ]; then
                    selected_files+=("${indexed_files[$j]}")
                fi
            done
        elif [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ -n "${indexed_files[$choice]}" ]; then
                selected_files+=("${indexed_files[$choice]}")
            fi
        fi
    done

    if [ ${#selected_files[@]} -eq 0 ]; then
        printf "\n${RED}[!] No valid files selected. Cancelled .gitignore generation.${RESET}\n"
        pause
        return
    fi

    local ignore_content="# Generated by $TOOLNAME on $(get_timestamp)\n"

    if [ "$mode" == "ignore" ]; then
        # Ignore Mode: Add selected files/dirs to ignore_content
        for file in "${selected_files[@]}"; do
            ignore_content+="/$file\n" # Add a leading slash to ignore only in the current directory
        done
        printf "\n${CYAN}[I] Ignoring selected files:${RESET}\n"
        printf "%s\n" "${selected_files[@]}" | awk -v CYAN="${CYAN}" -v RESET="${RESET}" '{print " " CYAN "- " $0 RESET}'
    elif [ "$mode" == "use" ]; then
        # Use Mode: Add all *unselected* files/dirs to ignore_content
        local kept_files=" ${selected_files[*]} "
        for file in "${all_files_array[@]}"; do
            if ! grep -q " ${file} " <<< "$kept_files"; then
                ignore_content+="/$file\n"
            fi
        done
        printf "\n${CYAN}[U] Keeping selected files (ignoring others):${RESET}\n"
        printf "%s\n" "${selected_files[@]}" | awk -v CYAN="${CYAN}" -v RESET="${RESET}" '{print " " CYAN "- " $0 RESET}'
    fi
    
    local final_content="$ignore_content"
    if [ -f .gitignore ]; then
        printf "\n${MAGENTA}[-] .gitignore already exists. Append new content? (y/N): ${RESET} "
        read -r append_confirm
        if [[ "$append_confirm" == "y" || "$append_confirm" == "Y" ]]; then
            printf "\n%s" "$final_content" >> .gitignore
            printf "${GREEN}[✔] Content appended to .gitignore.${RESET}\n"
        else
            printf "\n${YELLOW}[!] Skipping .gitignore update.${RESET}\n"
        fi
    else
        printf "%s" "$final_content" > .gitignore
        printf "${GREEN}[✔] .gitignore created successfully.${RESET}\n"
    fi
}
# END: Dynamic gitignore builder fix

git_push_auto() {
    if ! check_repo_exists "interactive"; then return; fi
    if ! check_internet; then pause; return; fi
    update_remote_url_with_token
    printf "\n${YELLOW} [ Auto Sync ]${RESET}\n\n"
    
    local timestamp_msg="AutoSync: $(get_timestamp)"
    
    _git_exec "Auto Add" add .
    
    set +e
    if git diff --cached --quiet; then
        set -e
        printf "\n${YELLOW}[!] No changes detected after adding. Skipping commit and push.${RESET}\n"
    else
        set -e
        _git_exec "Auto Commit" commit -m "$timestamp_msg"
        
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        _git_exec "Auto Push" push origin "$current_branch"
    fi
    pause
}

quick_workflow() {
    if ! check_repo_exists "interactive"; then return; fi
    if ! check_internet; then pause; return; fi
    update_remote_url_with_token
    printf "\n${YELLOW} [ Quick Commit & Push Workflow ]${RESET}\n\n"
    
    _git_exec "Status Check" status
    
    printf "${BLUE}[${TOOLNAME}]::[Commit Message]: ${RESET} "
    read -r commit_msg
    
    _git_exec "Add All" add .
    
    set +e
    if git diff --cached --quiet; then
        set -e
        printf "\n${YELLOW}[!] No changes staged for commit after adding. Skipping commit and push.${RESET}\n"
    else
        set -e
        _git_exec "Commit" commit -m "$commit_msg"
        
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        _git_exec "Push" push origin "$current_branch"
    fi
    pause
}


_git_pull_cli() {
    if ! check_repo_exists "cli"; then return 1; fi
    if ! check_internet; then return 1; fi
    update_remote_url_with_token
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    local rebase_flag=""
    
    if [[ "$1" == "rebase" ]]; then
        rebase_flag="--rebase"
        printf "\n${YELLOW}[${TOOLNAME}]::[CLI Pull %s using Rebase]${RESET}\n" "$current_branch"
    else
        printf "\n${YELLOW}[${TOOLNAME}]::[CLI Pull %s using Merge.]${RESET}\n" "$current_branch"
    fi
    
    _git_exec "Pull" pull $rebase_flag origin "$current_branch"
}

_git_push_cli() {
    if ! check_repo_exists "cli"; then return 1; fi
    if ! check_internet; then return 1; fi
    update_remote_url_with_token
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    local flags=""

    if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
        flags="--force-with-lease"
        printf "${RED}[!] WARNING: Using --force-with-lease for push.${RESET}\n"
    fi

    printf "\n${YELLOW}[${TOOLNAME}]::[CLI Push %s to origin]${RESET}\n" "$current_branch"
    _git_exec "Push" push $flags origin "$current_branch"
}

git_pull() {
    if ! check_repo_exists "interactive"; then return; fi
    if ! check_internet; then pause; return; fi
    update_remote_url_with_token
    printf "\n${YELLOW} [ Pull Remote Changes ] ${RESET}\n\n"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    printf "${MAGENTA}[Current Branch]: %s${RESET}\n" "$current_branch"
    
    printf "${BLUE}[${TOOLNAME}]::[Use '--rebase' instead of 'merge'? [y/N]: ${RESET} "
    read -r use_rebase
    
    if [[ "$use_rebase" == "y" || "$use_rebase" == "Y" ]]; then
        _git_exec "Pull Rebase" pull --rebase origin "$current_branch"
    else
        _git_exec "Pull Merge" pull origin "$current_branch"
    fi
    pause
}

git_push() {
    if ! check_repo_exists "interactive"; then return; fi
    if ! check_internet; then pause; return; fi
    update_remote_url_with_token
    printf "\n${YELLOW} [ Push Local Commits ]${RESET}\n\n"
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    printf "${MAGENTA}[Current Branch]: %s${RESET}\n" "$current_branch"
    
    printf "${BLUE}[${TOOLNAME}]::[Do you need to force-with-lease? (y/N)]: ${RESET} "
    read -r force_push
    
    local push_flags=()
    local exec_name="Push"
    if [[ "$force_push" == "y" || "$force_push" == "Y" ]]; then
        printf "${RED}[!] DANGEROUS: Using --force-with-lease.${RESET}\n"
        push_flags+=(--force-with-lease)
        exec_name="Force Push"
    fi

    local push_succeeded=0
    if _git_exec "$exec_name" push "${push_flags[@]}" origin "$current_branch"; then
        push_succeeded=1
    fi
    
    if [ "$push_succeeded" -eq 0 ] && [[ "$force_push" != "y" && "$force_push" != "Y" ]]; then
        printf "\n${RED}[!] Push failed (Likely needs upstream set or non-fast-forward).${RESET}\n"
        printf "\n${BLUE}[${TOOLNAME}]::[Set upstream [y/N]: ${RESET} " "$current_branch"
        read -r set_upstream
        if [[ "$set_upstream" == "y" || "$set_upstream" == "Y" ]]; then
            _git_exec "Set Upstream" push --set-upstream origin "$current_branch"
        fi
    fi

    pause
}

remote_config_menu() {
    if ! check_repo_exists "interactive"; then return; fi
    if ! check_internet; then pause; return; fi
    update_remote_url_with_token

    while true; do
        printf "\n${RED}  [ CONFIGURATIONS ]${RESET}\n\n"
        
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        local repo_root
        repo_root=$(get_repo_root)
        printf "\n${GREEN}  [Current Repo]: ${RESER}${MAGENTA}%s${RESET}\n" "$repo_root"
        printf "${GREEN}  [Branch  Name]: ${RESET}${MAGENTA}%s${RESET}\n\n" "$current_branch"

        printf "${YELLOW}  [1] List Remotes${RESET}\n"
        printf "${YELLOW}  [2] Change Remote URL${RESET}\n"
        printf "${YELLOW}  [3] Remove Remote${RESET}\n"
        printf "${YELLOW}  [4] Add Secondary Remote${RESET}\n"
        printf "${YELLOW}  [5] Prune Remote Branches${RESET}\n"
        printf "\n${RED} [X] Main Menu${RESET}\n\n"
        printf "${BLUE}[${TOOLNAME}]::[SELECT OPTION]:${RESET} "
        read -r choice

        case $choice in
            1)
                _git_exec "List Remotes" remote -v
                ;;
            2)
                printf "${BLUE}[${TOOLNAME}]::[Remote Name (e.g., origin)]: ${RESET} "
                read -r remote_name
                printf "${BLUE}[${TOOLNAME}]::[New URL]: ${RESET} "
                read -r new_url
                local token_url_new
                token_url_new=$(echo "$new_url" | sed "s#https://#https://$GITHUB_USERNAME:$GITHUB_TOKEN@#")
                _git_exec "Set Remote URL" remote set-url "$remote_name" "$token_url_new"
                ;;
            3)
                printf "${BLUE}[${TOOLNAME}]::[Remote Name to Remove]: ${RESET} "
                read -r remote_name
                _git_exec "Remove Remote" remote remove "$remote_name"
                ;;
            4)
                printf "${BLUE}[${TOOLNAME}]::[New Remote Name (e.g., upstream)]: ${RESET} "
                read -r remote_name
                printf "${BLUE}[${TOOLNAME}]::[New Remote URL]: ${RESET} "
                read -r new_url
                local token_url_new
                token_url_new=$(echo "$new_url" | sed "s#https://#https://$GITHUB_USERNAME:$GITHUB_TOKEN@#")
                _git_exec "Add Remote" remote add "$remote_name" "$token_url_new"
                ;;
            5) _git_exec "Prune Remote" remote prune origin ;;
            [Xx]) break ;;
            *) printf "${RED}[!] Invalid Option.${RESET}\n" ;;
        esac
        pause
    done
}

local_menu() {
    while true; do
        printf "\n${RED}  [ LOCAL MENU ]${RESET}\n\n"
        
        local current_branch
        set +e
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        set -e
        local repo_root
        repo_root=$(get_repo_root)
        
        if [ -n "$repo_root" ]; then
            printf "${MAGENTA}  [Current Repo]: %s${RESET}\n" "$repo_root"
            printf "${MAGENTA}  [Branch  Name]: %s${RESET}\n\n" "$current_branch"
        else
            printf "\n${RED}[!] ${RESET}${GREEN}Directory${RESET}${CYAN} %s ${RESET}${RED}is Not a Git Repository${RESET}\n\n" "$PWD"
        fi
        
        printf "${YELLOW}  [1] Status${RESET}\n"
        printf "${YELLOW}  [2] Add${RESET}\n"
        printf "${YELLOW}  [3] Commit${RESET}\n"
        printf "${YELLOW}  [4] History${RESET}\n"
        printf "${YELLOW}  [5] Diff Changes${RESET}\n"
        printf "${YELLOW}  [6] Undo Changes${RESET}\n"
        printf "${YELLOW}  [7] Stash Menu${RESET}\n"
        printf "${YELLOW}  [8] Tag Menu${RESET}\n\n"
        printf "${RED} [X] Main Menu${RESET}\n\n"
        printf "${BLUE}[${TOOLNAME}]::[SELECT OPTION]:${RESET} "
        read -r choice

        case $choice in
            1) git_status ;;
            2) git_add ;;
            3) git_commit ;;
            4) git_log ;;
            5) git_diff ;;
            6) git_undo ;;
            7) git_stash_menu ;;
            8) git_tag_menu ;;
            [Xx]) break ;;
            *) printf "\n${RED}[!] Invalid Option.${RESET}\n" ;;
        esac
    done
}

# START: Branch menu fix
branch_menu() {
    while true; do
        printf "\n${RED}  [ BRANCH MENU ]${RESET}\n"
        
        local current_branch
        set +e
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        set -e
        local repo_root
        repo_root=$(get_repo_root)
        
        if [ -n "$repo_root" ]; then
            printf "\n${MAGENTA}  [Current Repo]: %s${RESET}\n" "$repo_root"
            printf "${MAGENTA}  [Branch  Name]: %s${RESET}\n\n" "$current_branch"
        else
           printf "\n${RED}[!] ${RESET}${GREEN}Directory${RESET}${CYAN} %s ${RESET}${RED}is Not a Git Repository${RESET}\n\n" "$PWD"
        fi
        
        printf "${YELLOW}  [1] List All Branches${RESET}\n"
        printf "${YELLOW}  [2] Create & Switch Branch${RESET}\n"
        printf "${YELLOW}  [3] Merge Branch${RESET}\n"
        printf "${YELLOW}  [4] Rebase Branch${RESET}\n"
        printf "${YELLOW}  [5] Delete Local Branch${RESET}\n"
        printf "${YELLOW}  [6] Switch Branch${RESET}\n" # Added switch option
        printf "\n${RED} [X] Main Menu${RESET}\n\n"
        printf "${BLUE}[${TOOLNAME}]::[SELECT OPTION]:${RESET} "
        read -r choice

        case $choice in
            1) git_branch_list ;;
            2) git_branch_create_switch ;;
            3) git_branch_merge ;;
            4) git_branch_rebase ;;
            5) git_branch_delete ;;
            6) git_branch_switch ;; # Call the new switch function
            [Xx]) break ;;
            *) printf "\n${RED}[!] Invalid Option.${RESET}\n" ;;
        esac
    done
}
# END: Branch menu fix

user_profile_menu() {
    while true; do
        printf "\n${RED}  [ USERS PROFILE ]${RESET}\n\n"

        local git_user
        set +e
        git_user=$(git config user.name 2>/dev/null)
        local git_email
        git_email=$(git config user.email 2>/dev/null)
        set -e


        local cred_status
        if [[ -f "$CREDENTIALS_FILE" ]]; then
            local username
            username=$(jq -r '.username' "$CREDENTIALS_FILE" 2>/dev/null || echo "null")
            if [[ "$username" != "null" && -n "$username" ]]; then
                cred_status="${GREEN} ${username}${RESET}"
            else
                cred_status="${YELLOW}File Exists, but Empty/Invalid${RESET}"
            fi
        else
            cred_status="${RED}Missing${RESET}"
        fi
        

        printf "${CYAN}      [ GITHUB ]${RESET}\n"
        printf "\n${GREEN}    [USER]: ${RESET}${YELLOW}${git_user:-Not Set}${RESET}"
        printf "\n${GREEN}    [EMAIL]: ${RESET}${YELLOW}${git_email:-Not Set}${RESET}\n\n"
        printf "${MAGENTA}  [Username]: %b\n\n" "$cred_status"
        printf "${YELLOW}  [1] Add GitHub Credentials${RESET}\n"
        printf "${YELLOW}  [2] View GitHub Credentials${RESET}\n"
        printf "${YELLOW}  [3] Configure Global Git User${RESET}\n"
        printf "\n${RED} [X] Main Menu${RESET}\n\n"
        printf "${BLUE}[${TOOLNAME}]::[SELECT OPTION]:${RESET} "
        read -r choice

        case $choice in
            1) add_credentials ;;
            2) view_credentials ;;
            3) check_or_get_user_info; pause ;;
            [Xx]) break ;;
            *) printf "\n${RED}[!] Invalid Option.${RESET}\n" ;;
        esac
    done
}


process_cli_arguments() {
    local command="$1"
    local arg2="${2:-}"
    
    if ! check_repo_exists "cli" && [[ "$command" != "clone" ]]; then
        if [[ "$command" != "init" ]]; then
            return 1
        fi
    fi

    case "$command" in
        status) _git_exec "Status" status ;;
        add) _git_exec "Add" add "${arg2:-.}" ;;
        commit) 
            if [ -z "$arg2" ]; then 
                printf "${RED}Usage: laugit commit \"<message>\"${RESET}\n"; 
                return 1
            fi
            _git_exec "Commit" commit -m "$arg2" 
            ;;
        push) _git_push_cli "$arg2" ;;
        pull) _git_pull_cli "$arg2" ;;
        init) init_and_push ;;
        clone) clone_repo ;;
        quick) quick_workflow ;;
        log) git_log ;;
        stash) git_stash_menu ;;
        *) printf "${RED}[!] Invalid CLI command: %s${RESET}\n" "$command"; return 1 ;;
    esac
    return 0
}


main_menu() {
    mkdir -p "$CONFIG_DIR" "$LOGS_DIR"

    check_dependencies
    
    while true; do
        local NOW
        NOW=$(get_timestamp)
        
        load_credentials
        check_or_get_user_info
        
        printf "${RED}      [ M E N U ]${RESET}\n\n"
        
        local current_branch
        set +e
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        set -e
        local repo_root
        repo_root=$(get_repo_root)
        if [ -n "$repo_root" ]; then
            printf "${MAGENTA}  [Current Repo]: %s${RESET}\n" "$repo_root"
            printf "${MAGENTA}  [Branch  Name]: %s${RESET}\n\n" "$current_branch"
        fi

        printf "${CYAN}  [ LOCAL SETUP ]${RESET}\n\n"
        printf "${YELLOW}  [1] Initial Setup${RESET}\n"
        printf "${YELLOW}  [2] Cloning Repos${RESET}\n"
        printf "${YELLOW}  [3] Local   Menu${RESET}\n"
        printf "${YELLOW}  [4] Branch  Menu${RESET}\n"
        printf "\n${CYAN}  [ WORKFLOWS ]${RESET}\n\n"
        printf "${YELLOW}  [5] Auto Sync${RESET}\n"
        printf "${YELLOW}  [6] Quick Commit${RESET}\n"
        printf "${YELLOW}  [7] Push Commits${RESET}\n"
        printf "${YELLOW}  [8] Pull Changes${RESET}\n"
        printf "\n${CYAN}  [ CONFIGURATIONS ]${RESET}\n\n"
        printf "${YELLOW}  [9] Remote Config Menu${RESET}\n"
        printf "${YELLOW}  [P] Users Profile Menu${RESET}\n"
        printf "${YELLOW}  [G] Build a .gitignore${RESET}\n\n"
        printf "${RED} [X] Exit${RESET}\n\n"
        printf "${BLUE}[${TOOLNAME}]::[SELECT OPTION]:${RESET} "
        read -r choice

        case $choice in
            1) init_and_push ;;
            2) clone_repo ;;
            3) local_menu ;;
            4) branch_menu ;;
            5) git_push_auto ;;
            6) quick_workflow ;;
            7) git_push ;;
            8) git_pull ;;
            9) remote_config_menu ;;
            [Pp]) user_profile_menu ;;
            [Gg]) _build_gitignore; pause ;;
            [Xx])
                printf "\n${RED}  ╔═════════════════════╗${RESET}\n"
                printf "${RED}  ║     L A U G I T     ║${RESET}\n"
                printf "${CYAN}  ║ %s ║${RESET}\n" "$NOW"
                printf "${RED}  ║         B Y E       ║${RESET}\n"
                printf "${RED}  ╚═════════════════════╝${RESET}\n"
                exit 0 ;;
            *) 
            printf "\n"
            printf "${RED}[!] Invalid Option.${RESET}" 
            printf "\n" ;;
        esac
    done
}

# Check for CLI arguments
if [ "$#" -gt 0 ]; then
    process_cli_arguments "$@"
else
    # Run interactive menu if no arguments are passed
    main_menu "$@"
fi
