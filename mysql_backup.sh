#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# Treat unset variables as an error, and ensure failures in pipelines are not masked
set -euo pipefail

# Global constants
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
log_message "MySQL found: $MYSQL_VERSION" "info"

# Check MySQL config (~/.my.cnf) exists and works
if ! mysql --defaults-file=~/.my.cnf -e "SELECT 1" >/dev/null 2>&1; then
    log_message "MySQL config file (~/.my.cnf) is invalid or missing." "error"
    exit 1
fi
log_message "MySQL config file (~/.my.cnf) is valid." "info"

# Check mysqlpump exists and is executable
if ! command -v mysqlpump &> /dev/null; then
    log_message "mysqlpump not found or not executable." "error"
    exit 1
fi
log_message "mysqlpump exists and is executable." "info"

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
log_message "mysqlbinlog exists, binary logging enabled, binlog directory: $BINLOG_DIR" "info"

# Check gzip
if ! command -v gzip &> /dev/null; then
    log_message "gzip not found." "error"
    exit 1
fi
log_message "gzip exists and is executable." "info"

# Find MySQL data directory
DATA_DIR=$(mysql -e "SHOW VARIABLES LIKE 'datadir';" | awk 'NR==2{print $2}')
if [[ ! -d "$DATA_DIR" ]]; then
    log_message "MySQL data directory not found." "error"
    exit 1
fi
log_message "MySQL data directory found: $DATA_DIR" "info"

# Get list of non-system databases
ALL_DBS=$(mysql -N -e "SHOW DATABASES;" | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")
DB_COUNT=$(echo "$ALL_DBS" | wc -l)
log_message "User databases found ($DB_COUNT):\n$ALL_DBS" "info"

for DB_NAME in $ALL_DBS; do
    DB_DIR="$BACKUP_DIR/$DB_NAME"
    mkdir -p "$DB_DIR"

    # Check if full backup already exists
    if ls "$DB_DIR/${DB_NAME}_full_"*.gz &>/dev/null; then
        log_message "Starting incremental backup for '$DB_NAME'..." "info"
        LAST_FULL_POS_FILE="$DB_DIR/full_start.txt"
        if [[ ! -f "$LAST_FULL_POS_FILE" ]]; then
            log_message "No full_start.txt found for '$DB_NAME'. Cannot proceed with incremental." "error"
            exit 1
        fi

        read BINLOG_FILE START_POS < "$LAST_FULL_POS_FILE"
        read CUR_BINLOG CUR_POS <<< $(mysql -e "SHOW MASTER STATUS\G" | awk '/File:/ {file=$2} /Position:/ {pos=$2} END {print file,pos}')

        BINLOG_LIST=($(mysql -e "SHOW BINARY LOGS;" | awk 'NR>1 {print $1}'))
        FILES_TO_USE=()
        FOUND=0
        for f in "${BINLOG_LIST[@]}"; do
            [[ "$f" == "$BINLOG_FILE" ]] && FOUND=1
            [[ $FOUND -eq 1 ]] && FILES_TO_USE+=("$f")
            [[ "$f" == "$CUR_BINLOG" ]] && break
        done

        INC_FILE="$DB_DIR/${DB_NAME}_inc_${TIMESTAMP}.sql"
        mysqlbinlog --start-position="$START_POS" --stop-position="$CUR_POS" --database="$DB_NAME" "${FILES_TO_USE[@]/#/$BINLOG_DIR/}" > "$INC_FILE"
        gzip "$INC_FILE"
        log_message "Incremental backup complete: $(basename "$INC_FILE.gz")" "success"
    else
        log_message "Starting full backup for '$DB_NAME'..." "info"

        TABLE_INFO_FULL="$DB_DIR/table_info_full.txt"
        echo -e "database_name\ttable_name\ttable_rows" > "$TABLE_INFO_FULL"
        TABLES=$(mysql -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_type='BASE TABLE';")
        for TABLE in $TABLES; do
            ROWS=$(mysql -N -e "SELECT COUNT(*) FROM \`$DB_NAME\`.\`$TABLE\`;")
            echo -e "$DB_NAME\t$TABLE\t$ROWS" >> "$TABLE_INFO_FULL"
        done

        read BINLOG_FILE BINLOG_POS <<< $(mysql -e "SHOW MASTER STATUS\G" | awk '/File:/ {file=$2} /Position:/ {pos=$2} END {print file,pos}')
        echo "$BINLOG_FILE $BINLOG_POS" > "$DB_DIR/full_start.txt"

        FULL_BACKUP_FILE="$DB_DIR/${DB_NAME}_full_${TIMESTAMP}.sql"
        mysqlpump --single-transaction --defer-table-indexes=FALSE --databases "$DB_NAME" > "$FULL_BACKUP_FILE"
        gzip "$FULL_BACKUP_FILE"
        log_message "Full backup complete: $(basename "$FULL_BACKUP_FILE.gz")" "success"
    fi
done

log_message "All backups completed successfully." "success"