#!/bin/bash

#############################################
# OCI Backup Script - Enterprise Edition
# Version: 2.0.0
# Description: Automated backup to OCI Object Storage with 
#              error handling, logging, and retention policy
#############################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/backup.config"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Configuration file not found: ${CONFIG_FILE}${NC}"
    echo "Please create backup.config from backup.config.example"
    exit 1
fi
source "$CONFIG_FILE"

# Set defaults if not in config
: ${LOG_DIR:="${SCRIPT_DIR}/logs"}
: ${TEMP_DIR:="/tmp/oci-backups"}
: ${RETENTION_DAYS:=30}
: ${COMPRESSION_LEVEL:=6}
: ${ENABLE_ENCRYPTION:=false}
: ${DRY_RUN:=false}
: ${VERBOSE:=false}
: ${NOTIFICATION_WEBHOOK:=""}
: ${MAX_RETRIES:=3}
: ${RETRY_DELAY:=5}

# Create necessary directories
mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_DIR"

# Logging setup
LOG_FILE="${LOG_DIR}/backup_$(date +%Y%m%d).log"
ERROR_LOG="${LOG_DIR}/backup_errors_$(date +%Y%m%d).log"

# Logging functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$ERROR_LOG"
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
        *)
            echo "$message"
            echo "[$timestamp] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Error handler
error_handler() {
    local line_no=$1
    local exit_code=$2
    log ERROR "Script failed at line $line_no with exit code $exit_code"
    cleanup
    send_notification "ERROR" "Backup failed at line $line_no with exit code $exit_code"
    exit $exit_code
}

trap 'error_handler ${LINENO} $?' ERR

# Cleanup function
cleanup() {
    log DEBUG "Cleaning up temporary files..."
    if [[ -n "${BACKUP_FILE:-}" ]] && [[ -f "$BACKUP_FILE" ]]; then
        rm -f "$BACKUP_FILE"
        log DEBUG "Removed temporary backup file: $BACKUP_FILE"
    fi
}

trap cleanup EXIT

# Send notification
send_notification() {
    local status=$1
    local message=$2
    
    if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
        local color="good"
        [[ "$status" == "ERROR" ]] && color="danger"
        [[ "$status" == "WARN" ]] && color="warning"
        
        local payload=$(cat <<EOF
{
    "text": "OCI Backup Notification",
    "attachments": [{
        "color": "$color",
        "title": "Backup $status",
        "text": "$message",
        "footer": "$(hostname)",
        "ts": $(date +%s)
    }]
}
EOF
)
        curl -X POST -H 'Content-Type: application/json' \
             --data "$payload" "$NOTIFICATION_WEBHOOK" 2>/dev/null || true
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log INFO "Validating prerequisites..."
    
    # Check if OCI CLI is installed
    if ! command -v oci &> /dev/null; then
        log ERROR "OCI CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if OCI CLI is configured
    if ! oci iam region list &> /dev/null; then
        log ERROR "OCI CLI is not configured properly. Please run 'oci setup config'"
        exit 1
    fi
    
    # Validate folders to backup
    for folder in "${FOLDERS_TO_BACKUP[@]}"; do
        if [[ ! -d "$folder" ]]; then
            log ERROR "Folder does not exist: $folder"
            exit 1
        fi
    done
    
    # Check if bucket exists
    if ! oci os bucket get --bucket-name "$OCI_BUCKET" &> /dev/null; then
        log ERROR "OCI bucket does not exist or is not accessible: $OCI_BUCKET"
        exit 1
    fi
    
    log INFO "Prerequisites validated successfully"
}

# Calculate folder size
get_folder_size() {
    local folder=$1
    du -sh "$folder" 2>/dev/null | cut -f1
}

# Create backup archive
create_backup() {
    local backup_name=$1
    local folders=("${@:2}")
    
    log INFO "Creating backup archive: $backup_name"
    
    # Build tar command
    local tar_cmd="tar"
    
    # Add compression based on type
    case "${COMPRESSION_TYPE:-gzip}" in
        gzip)
            tar_cmd="$tar_cmd -czf"
            ;;
        bzip2)
            tar_cmd="$tar_cmd -cjf"
            ;;
        xz)
            tar_cmd="$tar_cmd -cJf"
            ;;
        none)
            tar_cmd="$tar_cmd -cf"
            ;;
        *)
            log WARN "Unknown compression type: $COMPRESSION_TYPE. Using gzip."
            tar_cmd="$tar_cmd -czf"
            ;;
    esac
    
    # Add compression level for gzip
    if [[ "${COMPRESSION_TYPE:-gzip}" == "gzip" ]]; then
        export GZIP="-$COMPRESSION_LEVEL"
    fi
    
    # Build exclude options
    local exclude_opts=""
    if [[ -n "${EXCLUDE_PATTERNS:-}" ]]; then
        IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
        for pattern in "${PATTERNS[@]}"; do
            exclude_opts="$exclude_opts --exclude='$pattern'"
        done
    fi
    
    # Calculate total size
    local total_size=0
    for folder in "${folders[@]}"; do
        local size=$(get_folder_size "$folder")
        log INFO "  - $folder: $size"
    done
    
    # Create the archive
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create archive: $backup_name"
        return 0
    fi
    
    eval $tar_cmd "$backup_name" $exclude_opts "${folders[@]}" 2>&1 | \
        while read line; do log DEBUG "$line"; done
    
    local archive_size=$(du -sh "$backup_name" 2>/dev/null | cut -f1)
    log INFO "Archive created successfully: $backup_name (Size: $archive_size)"
}

# Encrypt backup if enabled
encrypt_backup() {
    local backup_file=$1
    
    if [[ "$ENABLE_ENCRYPTION" != "true" ]]; then
        return 0
    fi
    
    log INFO "Encrypting backup..."
    
    if [[ -z "${ENCRYPTION_PASSWORD:-}" ]]; then
        log ERROR "Encryption enabled but ENCRYPTION_PASSWORD not set"
        exit 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would encrypt: $backup_file"
        return 0
    fi
    
    openssl enc -aes-256-cbc -salt -in "$backup_file" \
            -out "${backup_file}.enc" -pass pass:"$ENCRYPTION_PASSWORD"
    
    if [[ $? -eq 0 ]]; then
        mv "${backup_file}.enc" "$backup_file"
        log INFO "Backup encrypted successfully"
    else
        log ERROR "Failed to encrypt backup"
        exit 1
    fi
}

# Upload to OCI with retry logic
upload_to_oci() {
    local file=$1
    local object_name=$2
    local attempt=1
    
    log INFO "Uploading to OCI Object Storage..."
    log INFO "  Bucket: $OCI_BUCKET"
    log INFO "  Object: $object_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would upload: $file to $OCI_BUCKET/$object_name"
        return 0
    fi
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log DEBUG "Upload attempt $attempt of $MAX_RETRIES"
        
        if oci os object put \
            --bucket-name "$OCI_BUCKET" \
            --file "$file" \
            --name "$object_name" \
            --force \
            --no-multipart \
            2>&1 | while read line; do log DEBUG "$line"; done; then
            
            log INFO "Upload successful!"
            return 0
        else
            log WARN "Upload attempt $attempt failed"
            
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                log INFO "Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            fi
            
            ((attempt++))
        fi
    done
    
    log ERROR "Failed to upload after $MAX_RETRIES attempts"
    return 1
}

# Clean old backups from OCI
cleanup_old_backups() {
    if [[ $RETENTION_DAYS -le 0 ]]; then
        log DEBUG "Retention policy disabled (RETENTION_DAYS=$RETENTION_DAYS)"
        return 0
    fi
    
    log INFO "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%dT%H:%M:%S)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would check for backups older than $cutoff_date"
        return 0
    fi
    
    # List objects in bucket
    local old_backups=$(oci os object list \
        --bucket-name "$OCI_BUCKET" \
        --prefix "$BACKUP_PREFIX" \
        --query "data[?\"time-created\" < '$cutoff_date'].name" \
        --output tsv 2>/dev/null)
    
    if [[ -z "$old_backups" ]]; then
        log INFO "No old backups to remove"
        return 0
    fi
    
    # Delete old backups
    local count=0
    while IFS= read -r object_name; do
        if [[ -n "$object_name" ]]; then
            log INFO "  Deleting: $object_name"
            oci os object delete \
                --bucket-name "$OCI_BUCKET" \
                --object-name "$object_name" \
                --force 2>&1 | while read line; do log DEBUG "$line"; done
            ((count++))
        fi
    done <<< "$old_backups"
    
    log INFO "Removed $count old backup(s)"
}

# Verify backup
verify_backup() {
    local object_name=$1
    
    log INFO "Verifying backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would verify: $object_name"
        return 0
    fi
    
    # Get object metadata
    if oci os object head \
        --bucket-name "$OCI_BUCKET" \
        --object-name "$object_name" &> /dev/null; then
        log INFO "Backup verified successfully in OCI"
        return 0
    else
        log ERROR "Failed to verify backup in OCI"
        return 1
    fi
}

# Generate backup report
generate_report() {
    local start_time=$1
    local end_time=$2
    local backup_file=$3
    local success=$4
    
    local duration=$((end_time - start_time))
    local report_file="${LOG_DIR}/backup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" <<EOF
=====================================
OCI BACKUP REPORT
=====================================
Date: $(date)
Hostname: $(hostname)
User: $(whoami)

Backup Configuration:
- Folders: ${FOLDERS_TO_BACKUP[@]}
- Bucket: $OCI_BUCKET
- Prefix: $BACKUP_PREFIX
- Compression: ${COMPRESSION_TYPE:-gzip}
- Encryption: $ENABLE_ENCRYPTION
- Retention: $RETENTION_DAYS days

Execution:
- Start Time: $(date -d @$start_time)
- End Time: $(date -d @$end_time)
- Duration: $duration seconds
- Status: $([ "$success" == "true" ] && echo "SUCCESS" || echo "FAILED")

Backup File:
- Name: $(basename ${backup_file:-N/A})
- Size: $([ -f "${backup_file:-}" ] && du -sh "$backup_file" | cut -f1 || echo "N/A")

Logs:
- Main Log: $LOG_FILE
- Error Log: $ERROR_LOG
=====================================
EOF
    
    log INFO "Report generated: $report_file"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log INFO "DRY RUN MODE ENABLED"
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --config|-c)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat <<EOF
OCI Backup Script v2.0.0

Usage: $0 [OPTIONS]

Options:
    --dry-run        Run without actually creating or uploading backups
    --verbose, -v    Enable verbose output
    --config, -c     Specify alternate config file
    --help, -h       Show this help message

Configuration:
    Edit backup.config to set:
    - Folders to backup
    - OCI bucket details
    - Retention policy
    - Notification settings
    - And more...

Examples:
    # Normal backup
    $0
    
    # Dry run to test configuration
    $0 --dry-run
    
    # Verbose output for debugging
    $0 --verbose
    
    # Use different config
    $0 --config /path/to/config

EOF
}

# Main execution
main() {
    local start_time=$(date +%s)
    local success=false
    
    log INFO "========================================="
    log INFO "OCI Backup Script Started"
    log INFO "========================================="
    
    # Validate prerequisites
    validate_prerequisites
    
    # Generate backup filename
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname=$(hostname -s)
    local backup_filename="${BACKUP_PREFIX}_${hostname}_${timestamp}.tar"
    
    # Add compression extension
    case "${COMPRESSION_TYPE:-gzip}" in
        gzip)  backup_filename="${backup_filename}.gz" ;;
        bzip2) backup_filename="${backup_filename}.bz2" ;;
        xz)    backup_filename="${backup_filename}.xz" ;;
    esac
    
    # Add encryption extension if enabled
    [[ "$ENABLE_ENCRYPTION" == "true" ]] && backup_filename="${backup_filename}.enc"
    
    BACKUP_FILE="${TEMP_DIR}/${backup_filename}"
    
    # Create backup
    create_backup "$BACKUP_FILE" "${FOLDERS_TO_BACKUP[@]}"
    
    # Encrypt if enabled
    encrypt_backup "$BACKUP_FILE"
    
    # Upload to OCI
    if upload_to_oci "$BACKUP_FILE" "$backup_filename"; then
        success=true
        
        # Verify backup
        verify_backup "$backup_filename"
        
        # Clean old backups
        cleanup_old_backups
        
        log INFO "Backup completed successfully!"
        send_notification "SUCCESS" "Backup completed: $backup_filename"
    else
        log ERROR "Backup failed!"
        send_notification "ERROR" "Backup failed: $backup_filename"
    fi
    
    # Generate report
    local end_time=$(date +%s)
    generate_report $start_time $end_time "$BACKUP_FILE" $success
    
    log INFO "========================================="
    log INFO "OCI Backup Script Finished"
    log INFO "========================================="
    
    [[ "$success" == "true" ]] && exit 0 || exit 1
}

# Parse arguments and run
parse_arguments "$@"
main