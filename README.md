# OCI Backup Script - Enterprise Edition

[![Version](https://img.shields.io/badge/Version-2.0.0-blue.svg)](https://github.com/yourusername/oci-backup-script)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![OCI](https://img.shields.io/badge/Oracle-Cloud-red.svg)](https://www.oracle.com/cloud/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A robust, enterprise-grade bash script for automated backups to Oracle Cloud Infrastructure (OCI) Object Storage with advanced features including error handling, logging, retention policies, encryption, and notifications.

## 🚀 Features

### Core Functionality
- **Automated Backups** - Schedule regular backups of multiple folders
- **OCI Object Storage** - Secure cloud storage with Oracle Cloud Infrastructure
- **Compression** - Support for gzip, bzip2, xz, or no compression
- **Encryption** - Optional AES-256 encryption for sensitive data
- **Retention Policy** - Automatic cleanup of old backups

### Advanced Features
- **Error Handling** - Comprehensive error detection and recovery
- **Retry Logic** - Automatic retry on upload failures
- **Progress Logging** - Detailed logs with multiple verbosity levels
- **Dry Run Mode** - Test configuration without performing actual backup
- **Notifications** - Webhook support for Slack, Discord, etc.
- **Exclude Patterns** - Skip unwanted files/folders
- **Backup Verification** - Verify successful upload to OCI
- **Reports** - Generate detailed backup reports

### Monitoring & Observability
- **Colored Output** - Easy-to-read terminal output
- **Separate Error Logs** - Dedicated error tracking
- **Backup Reports** - Detailed execution reports
- **Size Calculation** - Show folder and archive sizes
- **Performance Metrics** - Track backup duration

## 📋 Prerequisites

### Required
- Bash 4.0+
- OCI CLI installed and configured
- Access to an OCI Object Storage bucket
- Standard Unix tools: tar, gzip, curl, openssl

### Optional
- bzip2 (for bzip2 compression)
- xz (for xz compression)
- mail (for email notifications)

## 🛠️ Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/oci-backup-script.git
cd oci-backup-script

# Run the installation script
chmod +x install.sh
./install.sh
```

### Manual Installation

1. **Install OCI CLI** (if not already installed):
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

2. **Configure OCI CLI**:
```bash
oci setup config
```

3. **Setup the backup script**:
```bash
# Make script executable
chmod +x backup.sh

# Copy and edit configuration
cp backup.config.example backup.config
nano backup.config

# Create logs directory
mkdir -p logs
```

## ⚙️ Configuration

Edit `backup.config` to customize your backup settings:

```bash
# Folders to backup
FOLDERS_TO_BACKUP=(
    "/home/user/documents"
    "/var/www/html"
    "/etc/nginx"
)

# OCI settings
OCI_BUCKET="my-backup-bucket"
BACKUP_PREFIX="prod-backup"

# Retention (days)
RETENTION_DAYS=30

# Compression (gzip/bzip2/xz/none)
COMPRESSION_TYPE="gzip"
COMPRESSION_LEVEL=6

# Encryption
ENABLE_ENCRYPTION=true
ENCRYPTION_PASSWORD="your-strong-password"

# Notifications
NOTIFICATION_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `FOLDERS_TO_BACKUP` | Array of folders to backup | Required |
| `OCI_BUCKET` | OCI Object Storage bucket name | Required |
| `BACKUP_PREFIX` | Prefix for backup file names | "backup" |
| `RETENTION_DAYS` | Days to keep old backups (0=forever) | 30 |
| `COMPRESSION_TYPE` | gzip, bzip2, xz, or none | "gzip" |
| `COMPRESSION_LEVEL` | 1-9 (higher=better compression) | 6 |
| `ENABLE_ENCRYPTION` | Enable AES-256 encryption | false |
| `EXCLUDE_PATTERNS` | Comma-separated exclude patterns | "*.log,*.tmp" |
| `NOTIFICATION_WEBHOOK` | Webhook URL for notifications | "" |
| `MAX_RETRIES` | Upload retry attempts | 3 |
| `VERBOSE` | Enable verbose output | false |

## 🚀 Usage

### Basic Usage

```bash
# Run backup
./backup.sh

# Dry run (test without backing up)
./backup.sh --dry-run

# Verbose output
./backup.sh --verbose

# Use custom config
./backup.sh --config /path/to/config

# Help
./backup.sh --help
```

### Test Your Configuration

```bash
# Run the test script
./test-backup.sh
```

### Schedule Automatic Backups

Add to crontab for scheduled backups:

```bash
# Edit crontab
crontab -e

# Add one of these lines:
# Daily at 2 AM
0 2 * * * /path/to/backup.sh

# Weekly on Sunday at 2 AM
0 2 * * 0 /path/to/backup.sh

# Monthly on the 1st at 2 AM
0 2 1 * * /path/to/backup.sh
```

## 📁 Directory Structure

```
oci-backup-script/
├── backup.sh              # Main backup script
├── backup.config          # Your configuration (create from example)
├── backup.config.example  # Configuration template
├── install.sh            # Installation script
├── test-backup.sh        # Test script (created by installer)
├── logs/                 # Log files directory
│   ├── backup_YYYYMMDD.log
│   ├── backup_errors_YYYYMMDD.log
│   └── backup_report_*.txt
└── README.md            # This file
```

## 📊 Backup Workflow

1. **Validation** - Check prerequisites and configuration
2. **Archive Creation** - Create compressed tar archive
3. **Encryption** (optional) - Encrypt archive with AES-256
4. **Upload** - Upload to OCI with retry logic
5. **Verification** - Verify successful upload
6. **Cleanup** - Remove old backups per retention policy
7. **Notification** - Send success/failure notifications
8. **Report** - Generate detailed backup report

## 🔍 Monitoring

### Log Files

- **Main Log**: `logs/backup_YYYYMMDD.log` - All backup operations
- **Error Log**: `logs/backup_errors_YYYYMMDD.log` - Errors only
- **Reports**: `logs/backup_report_*.txt` - Detailed execution reports

### Log Levels

- `ERROR` - Critical errors that stop execution
- `WARN` - Warnings that don't stop execution
- `INFO` - General information about backup progress
- `DEBUG` - Detailed debugging information (verbose mode)

### Example Log Output

```
[2024-01-15 02:00:00] [INFO] OCI Backup Script Started
[2024-01-15 02:00:01] [INFO] Validating prerequisites...
[2024-01-15 02:00:02] [INFO] Creating backup archive: backup_prod_20240115_020000.tar.gz
[2024-01-15 02:00:45] [INFO] Archive created successfully (Size: 1.2G)
[2024-01-15 02:00:46] [INFO] Uploading to OCI Object Storage...
[2024-01-15 02:02:15] [INFO] Upload successful!
[2024-01-15 02:02:16] [INFO] Backup verified successfully in OCI
[2024-01-15 02:02:17] [INFO] Removed 2 old backup(s)
[2024-01-15 02:02:18] [INFO] Backup completed successfully!
```

## 🔒 Security Best Practices

1. **Protect Configuration File**:
```bash
chmod 600 backup.config
```

2. **Use Strong Encryption Password**:
- Minimum 16 characters
- Mix of letters, numbers, symbols
- Store securely (consider using OCI Vault)

3. **Secure OCI Credentials**:
```bash
chmod 600 ~/.oci/config
chmod 600 ~/.oci/oci_api_key.pem
```

4. **Limit Bucket Access**:
- Use IAM policies to restrict bucket access
- Enable versioning on the bucket
- Consider using bucket encryption

## 🚨 Troubleshooting

### Common Issues

#### OCI CLI Not Found
```bash
# Install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

#### OCI Authentication Failed
```bash
# Reconfigure OCI CLI
oci setup config

# Test connection
oci iam region list
```

#### Permission Denied
```bash
# Make script executable
chmod +x backup.sh

# Fix config permissions
chmod 600 backup.config
```

#### Bucket Not Found
```bash
# List available buckets
oci os bucket list --compartment-id <your-compartment-id>

# Create bucket if needed
oci os bucket create --name my-backup-bucket --compartment-id <your-compartment-id>
```

### Debug Mode

Run with verbose output for detailed debugging:
```bash
./backup.sh --verbose --dry-run
```

Check logs for detailed error information:
```bash
tail -f logs/backup_errors_$(date +%Y%m%d).log
```

## 📈 Performance Tips

1. **Compression Level**: Lower levels (1-3) are faster but larger
2. **Exclude Patterns**: Exclude large unnecessary files
3. **Parallel Uploads**: Large files use multipart upload automatically
4. **Network**: Ensure good bandwidth to OCI region
5. **Local Storage**: Ensure sufficient space in TEMP_DIR

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Oracle Cloud Infrastructure team for excellent documentation
- The open source community for inspiration and tools

## 📮 Support

For issues, questions, or suggestions:
- Open an issue on [GitHub](https://github.com/yourusername/oci-backup-script/issues)
- Check the [Wiki](https://github.com/yourusername/oci-backup-script/wiki) for additional documentation

## 📊 Changelog

### Version 2.0.0 (2024)
- Complete rewrite with enterprise features
- Added error handling and retry logic
- Implemented retention policies
- Added encryption support
- Comprehensive logging system
- Dry-run mode
- Notification support
- Backup verification

### Version 1.0.0 (Original)
- Basic backup functionality
- Simple upload to OCI

---

⭐ If this script helps you, please consider giving it a star on GitHub!