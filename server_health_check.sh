#!/usr/bin/env bash
#
# server_health_check.sh
#
# A DevOps capstone project script to check the health
# of multiple remote servers via SSH.
#
# Usage: ./server_health_check.sh -f <server_list_file> -u <remote_user>
#
# --- Part 1: "Strict Mode" (from section 9) ---
# set -e: exit immediately if any command fails
# set -u: exit if an undefined variable is used
# set -o pipefail: if any command in a pipeline fails, treat the whole pipeline as failed
set -euo pipefail

LOG_FILE=$(mktemp /tmp/server_health_check.XXXXXX)
readonly LOG_FILE
cleanup() {
    echo "Cleaning up temporary files..."
    rm -f "$LOG_FILE"
}
trap cleanup EXIT INT TERM
echo "Script started. Log file: $LOG_FILE"

log_info() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $message" | tee -a "$LOG_FILE"
}
log_error() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $message" | tee -a "$LOG_FILE" >&2
}
print_usage() {
    echo "Usage: $0 -f <server_list_file> -u <remote_user>"
    echo "  -f: Path to the file containing the list of servers (one per line)"
    echo "  -u: Remote user to use for SSH connections"
    echo "  -h: Show this help message"
}

check_server(){
    local server="$1"
    local user="$2"
    log_info "--- Checking Server: $server ---"
    ssh -n -o ConnectTimeout=5 "${user}@${server}" << 'EOF'
        # 1. Uptime Check
        echo "--- System Uptime ---"
        uptime
        # 2. Disk Check (Root partition)
        echo "--- Disk Usage (Root /) ---"
        # NR==2 means print only the second line of df output
        df -h / | awk 'NR==2 {print "Used: " $5 " (" $3 "/" $2 ")"}'
        # 3. Memory Check
        echo "--- Memory Usage ---"
        free -m | awk 'NR==2 {
        printf "Used: %sMB / Total: %sMB (%.2f%%)\n", $3, $2, ($3/$2)*100
        }'
        # 4. Security Check (SSH brute-force failures)
            echo "--- Security (SSH) ---"
            AUTH_LOG="/var/log/auth.log"
            if [[ -f "$AUTH_LOG" ]]; then
                count=$(grep -c "Failed password" "$AUTH_LOG")
                echo "Failed SSH Attempts: $count"
            else
                echo "Failed SSH Attempts: auth log not found."
        fi
EOF
    log_info "--- Finished Check: $server ---"
}
main(){
    local server_list_file=""
    local remote_user=""
    #input parsing
    while getopts ":f:u:h" opt; do
        case $opt in
            f) server_list_file="$OPTARG" ;;
            u) remote_user="$OPTARG" ;;
            h) print_usage; exit 0 ;;
            \?) log_error "Invalid option: -$OPTARG"
                print_usage
                exit 1 ;;
            :) log_error "Option -$OPTARG requires an argument."
                print_usage
                exit 1 ;;
        esac
    done
    # input validation
    if [[ -z "$server_list_file" || -z "$remote_user" ]]; then
        log_error "Both -f (server list file) and -u (remote user) options are required."
        print_usage
        exit 1
    fi
    if [[ ! -f "$server_list_file" ]]; then
        log_error "Server list file not found: $server_list_file"
        exit 1
    fi

    log_info "Starting server health check for servers listed in: $server_list_file"
    declare -a servers
    while IFS= read -r server; do
        if [[ -z "$server" || "$server" == \#* ]]; then continue; fi
        servers+=("$server")
    done < "$server_list_file"
    if [[ ${#servers[@]} -eq 0 ]]; then
        log_error "No valid servers found in the list."
        exit 1
    fi
    log_info "Found ${#servers[@]} servers to check. Starting..."
    for server in "${servers[@]}"; do
        check_server "$server" "$remote_user"
    done
    log_info "Server health check completed."
}
main "$@"