#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and ensure failures in pipelines are not masked
set -euo pipefail

# Global constants (configurable via environment variables)
LOG_FILE="${LOG_FILE:-/home/ubuntu/logs/mysql_backup_restore.log}"
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}"
MYSQL_USER="${MYSQL_USER:-root}"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")

# ANSI colors for terminal output
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[32m'
COLOR_BLUE='\033[34m'
COLOR_RED='\033[31m'
COLOR_CYAN='\033[36m'

# Log message with type indication
log_message() {
    local MSG="$1"
    local TYPE="$2"
    echo "$MSG" >> "$LOG_FILE"

    case "$TYPE" in
        "error") echo -e "${COLOR_RED}$MSG${COLOR_RESET}" ;;
        "success") echo -e "${COLOR_GREEN}$MSG${COLOR_RESET}" ;;
        "info") echo -e "${COLOR_BLUE}$MSG${COLOR_RESET}" ;;
        *) echo -e "${COLOR_CYAN}$MSG${COLOR_RESET}" ;;
    esac
}

# Check and create required directories
mkdir -p "$BACKUP_DIR" && mkdir -p "$(dirname "$LOG_FILE")"
log_message "Directories for backup and log exist." "info"

# Check for MySQL binary and version
if ! command -v mysql &> /dev/null; then
    log_message "MySQL binary not found. Aborting." "error"
    exit 1
fi
MYSQL_VERSION=$(mysql --version)
log_message "MySQL: $MYSQL_VERSION" "info"

# Check MySQL config (~/.my.cnf) exists and works
if ! mysql --defaults-file=~/.my.cnf -e "SELECT 1" >/dev/null 2>&1; then
    log_message "MySQL config is invalid." "error"
    exit 1
fi
log_message "MySQL config is valid." "info"

# Check mysqlpump exists
if ! command -v mysqlpump &> /dev/null; then
    log_message "mysqlpump not found or not executable." "error"
    exit 1
fi
log_message "mysqlpump exists." "info"

# Check mysqlbinlog and binlog config
if ! command -v mysqlbinlog &> /dev/null; then
    log_message "mysqlbinlog not found." "error"
    exit 1
fi
BINLOG_ENABLED=$(mysql -e "SHOW VARIABLES LIKE 'log_bin';" | awk 'NR==2{print $2}')
if [[ "$BINLOG_ENABLED" != "ON" ]]; then
    log_message "Binary logging is not enabled." "error"
    exit 1
fi
BINLOG_BASE=$(mysql -e "SHOW VARIABLES LIKE 'log_bin_basename'\G" | awk '/Value:/ {print $2}')
BINLOG_DIR=$(dirname "$BINLOG_BASE")
log_message "Binlog dir: $BINLOG_DIR" "info"

# Check gzip
if ! command -v gzip &> /dev/null; then
    log_message "gzip not found." "error"
    exit 1
fi
log_message "gzip exists." "info"

# Find MySQL data directory
DATA_DIR=$(mysql -e "SHOW VARIABLES LIKE 'datadir';" | awk 'NR==2{print $2}')
if [[ ! -d "$DATA_DIR" ]]; then
    log_message "MySQL data directory not found." "error"
    exit 1
fi
log_message "Data directory: $DATA_DIR" "info"

# Get list of non-system databases
ALL_DBS=$(mysql -N -e "SHOW DATABASES;" | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")
DB_COUNT=$(echo "$ALL_DBS" | wc -l)
log_message "User databases found ($DB_COUNT):\n$ALL_DBS" "info"

for DB_NAME in $ALL_DBS; do
    log_message "Checking backup for database: $DB_NAME" "info"
    DB_DIR="$BACKUP_DIR/$DB_NAME"
    LATEST_FULL=$(ls -1 "$DB_DIR/${DB_NAME}_full_"*.gz 2>/dev/null | sort -r | tail -n 1)

    if [[ -n "$LATEST_FULL" ]]; then
        log_message "Restoring full backup for $DB_NAME: $(basename "$LATEST_FULL")" "info"
        mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;"
        gunzip -c "$LATEST_FULL" | mysql "$DB_NAME"

        LATEST_INC=$(ls -1 "$DB_DIR/${DB_NAME}_inc_"*.gz 2>/dev/null | sort -r | tail -n 1)
        if [[ -n "$LATEST_INC" ]]; then
            log_message "Restoring incremental backup for $DB_NAME: $(basename "$LATEST_INC")" "info"
            gunzip -c "$LATEST_INC" | mysql "$DB_NAME"
        fi
    else
        log_message "No full backup found for $DB_NAME. Skipping restore." "error"
    fi
done

log_message "Restore process completed." "success"
