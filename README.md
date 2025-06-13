# MySQL Backup and Restore Utility

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![ShellCheck](https://github.com/yashkhokhar28/mysql-backup-utility/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/yashkhokhar28/mysql-backup-utility/actions)

A robust Bash utility for automating MySQL database backups and restores, supporting both full and incremental backups using `mysqlpump`, `mysqlbinlog`, and `gzip`. Designed for Linux/Unix environments, this utility simplifies database management with detailed logging and error handling.

## Features

- **Full Backups**: Creates compressed SQL dumps of MySQL databases using `mysqlpump`.
- **Incremental Backups**: Captures changes via MySQL binlogs for efficient updates after a full backup.
- **Restore**: Restores databases from full and incremental backups, ensuring data recovery.
- **Logging**: Generates detailed logs with timestamps for debugging and auditing.
- **Error Handling**: Validates MySQL configuration, binary logging, and dependencies before execution.
- **Color-Coded Output**: Enhances CLI usability with color-coded terminal messages.

## Prerequisites

Before running the scripts, ensure the following are installed and configured:

- **Operating System**: Ubuntu or another Linux distribution (tested on Ubuntu 20.04/22.04).
- **MySQL/MariaDB**: Version 5.6 or higher, with `mysql`, `mysqlpump`, and `mysqlbinlog` binaries.
  - Tested with MySQL 8.0.27 (MySQL Community Server - GPL).
- **Binary Logging**: Enabled in MySQL configuration (`log_bin = ON` in `my.cnf`).
- **gzip**: Installed for compression (`sudo apt install gzip` on Ubuntu).
- **Bash**: Version 4 or later.
- **MySQL Configuration**:
  - A `~/.my.cnf` file with valid MySQL credentials, e.g.:
    ```ini
    [client]
    user=myuser
    password=mypassword
    ```
  - The MySQL user must have the following privileges: `SELECT`, `RELOAD`, `LOCK TABLES`, `BACKUP_ADMIN`, `REPLICATION SLAVE`.
- **Permissions**:
  - Write access to the backup directory (`/home/ubuntu/backups` by default).
  - Write access to the log directory (`/home/ubuntu/logs` by default).
  - Read access to the MySQL binlog directory (typically `/var/lib/mysql`).
- **Disk Space**: Sufficient space in the backup directory for SQL dumps and compressed files.

## Installation

1. Clone the repository (replace `your-username` with your GitHub username):

   ```bash
   git clone https://github.com/your-username/mysql-backup-utility.git
   cd mysql-backup-utility
   ```

2. Make the scripts executable:

   ```bash
   chmod +x mysql_backup.sh mysql_restore.sh
   ```

3. (Optional) Customize environment variables in the scripts or set them externally:
   ```bash
   export BACKUP_DIR="/custom/path/to/backups"
   export LOG_FILE="/custom/path/to/logs/mysql_backup_restore.log"
   export MYSQL_USER="backup_user"
   ```

## Directory Structure

```
mysql-backup-utility/
├── mysql_backup.sh
├── mysql_restore.sh
├── README.md
├── LICENSE.md
├── CHANGELOG.md
└── .gitignore
```

## Usage

### Backup Script (`mysql_backup.sh`)

Performs full or incremental backups of all non-system MySQL databases.

```bash
./mysql_backup.sh
```

- **Options** (set as environment variables):
  - `BACKUP_DIR`: Directory for backup files (default: `/home/ubuntu/backups`).
  - `LOG_FILE`: Path to the log file (default: `/home/ubuntu/logs/mysql_backup_restore.log`).
  - `MYSQL_USER`: MySQL user (default: `root`).
- **Behavior**:
  - Creates full backups for new databases using `mysqlpump` (`<db>_full_<timestamp>.sql.gz`).
  - Creates incremental backups using `mysqlbinlog` if a full backup exists (`<db>_inc_<timestamp>.sql.gz`).
  - Logs all actions to `LOG_FILE` with color-coded terminal output.

### Restore Script (`mysql_restore.sh`)

Restores databases from the latest full and incremental backups.

```bash
./mysql_restore.sh
```

- **Options**: Same as backup script (environment variables).
- **Behavior**:
  - Drops and recreates each database before restoring the latest full backup.
  - Applies the latest incremental backup, if available.
  - Logs all actions to `LOG_FILE` with color-coded output.

## Testing

To verify the scripts work correctly:

1. Ensure prerequisites are met (MySQL 8.0.27, `mysqlpump`, `mysqlbinlog`, `gzip`, binary logging enabled).
2. Run the backup script:
   ```bash
   ./mysql_backup.sh
   ```
3. Check the backup directory (`/home/ubuntu/backups`) for `<db>_full_<timestamp>.sql.gz` files.
4. Run the restore script:
   ```bash
   ./mysql_restore.sh
   ```
5. Verify the restored databases in MySQL:
   ```bash
   mysql -e "SHOW DATABASES;"
   ```
6. Check the log file (`/home/ubuntu/logs/mysql_backup_restore.log`) for errors or success messages.

## Configuration Recommendations

- **Security**:

  - Use a dedicated MySQL user with minimal privileges instead of `root`.
  - Secure `~/.my.cnf` with restrictive permissions:
    ```bash
    chmod 600 ~/.my.cnf
    ```
  - Schedule backups using `cron` with a dedicated user account:
    ```bash
    crontab -e
    # Run backup daily at 2 AM
    0 2 * * * /path/to/mysql-backup-utility/mysql_backup.sh
    ```

- **Portability**:

  - Test scripts on target systems to ensure compatibility with MySQL/MariaDB versions.
  - Consider adding command-line arguments for specific databases or custom paths (future enhancement).

- **Backup Rotation**:
  - To manage disk space, implement a rotation policy to delete backups older than 7 days:
    ```bash
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
    ```
  - Add this to a cron job or script for automation.

## Troubleshooting

- **Error**: `grep: ^(information_schema|performance_schema|mysql,|mys)$: No such file or directory`:
  - Caused by a malformed `grep` command in earlier versions of `mysql_restore.sh`.
  - Fixed in version 1.0.0 by correcting the regex to `grep -Ev "^(information_schema|performance_schema|mysql|sys)$"`.
  - Update to the latest script version from the repository.
- **Error**: `Binary logging not enabled`:
  - Enable binary logging in `my.cnf`:
    ```ini
    [mysqld]
    log_bin = mysql-bin
    ```
  - Restart MySQL:
    ```bash
    sudo systemctl restart mysql
    ```
- **Error**: Insufficient permissions:
  - Verify write access to `BACKUP_DIR` and `LOG_FILE` directories.
  - Grant required MySQL privileges:
    ```sql
    GRANT SELECT, RELOAD, LOCK TABLES, BACKUP_ADMIN, REPLICATION SLAVE ON *.* TO 'backup_user'@'localhost';
    ```
- **Error**: `mysqlpump not found`:
  - Install MySQL utilities:
    ```bash
    sudo apt install mysql-client
    ```
- Check logs in `LOG_FILE` for detailed error messages.

## Contributing

Contributions are welcome! Please:

1. Fork the repository.
2. Create a feature branch:
   ```bash
   git checkout -b feature/new-feature
   ```
3. Commit changes:
   ```bash
   git commit -am 'Add new feature'
   ```
4. Push to the branch:
   ```bash
   git push origin feature/new-feature
   ```
5. Open a pull request.

## Versioning

- Current version: 1.0.0

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE.md) file for details.

## Acknowledgments

- Built using standard Linux/Unix tools and MySQL utilities.
- Inspired by the need for reliable, automated MySQL backups in production environments.

---

Feel free to open issues for bugs or feature requests!
