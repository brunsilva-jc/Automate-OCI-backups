#!/bin/bash

#############################################
# OCI Backup Script - Installation Script
# Version: 2.0.0
#############################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  OCI Backup Script Installation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${YELLOW}Warning: Running as root. Consider running as a regular user.${NC}"
   echo
fi

# Function to check command existence
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        return 1
    fi
}

# Function to install OCI CLI
install_oci_cli() {
    echo -e "${YELLOW}Installing OCI CLI...${NC}"
    
    # Download and run the installer
    bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" \
        -- --accept-all-defaults
    
    # Add to PATH
    export PATH=$PATH:$HOME/bin
    
    echo -e "${GREEN}OCI CLI installed successfully${NC}"
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
echo

# Check for required commands
MISSING_DEPS=0

check_command "curl" || MISSING_DEPS=1
check_command "tar" || MISSING_DEPS=1
check_command "gzip" || MISSING_DEPS=1
check_command "openssl" || MISSING_DEPS=1

# Check for OCI CLI
if ! check_command "oci"; then
    echo
    echo -e "${YELLOW}OCI CLI is not installed.${NC}"
    read -p "Would you like to install it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_oci_cli
    else
        echo -e "${RED}OCI CLI is required. Please install it manually.${NC}"
        echo "Visit: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
        exit 1
    fi
fi

# Check for optional commands
echo
echo -e "${BLUE}Checking optional dependencies...${NC}"
check_command "bzip2" || echo "  (Optional for bzip2 compression)"
check_command "xz" || echo "  (Optional for xz compression)"
check_command "mail" || echo "  (Optional for email notifications)"

if [[ $MISSING_DEPS -eq 1 ]]; then
    echo
    echo -e "${RED}Some required dependencies are missing.${NC}"
    echo "Please install them using your package manager:"
    echo "  Ubuntu/Debian: sudo apt-get install curl tar gzip openssl"
    echo "  RHEL/CentOS: sudo yum install curl tar gzip openssl"
    echo "  macOS: brew install curl tar gzip openssl"
    exit 1
fi

echo
echo -e "${BLUE}Setting up backup script...${NC}"

# Make backup.sh executable
chmod +x backup.sh
echo -e "${GREEN}✓${NC} Made backup.sh executable"

# Create config file if it doesn't exist
if [[ ! -f "backup.config" ]]; then
    if [[ -f "backup.config.example" ]]; then
        cp backup.config.example backup.config
        echo -e "${GREEN}✓${NC} Created backup.config from example"
        echo -e "${YELLOW}  Please edit backup.config with your settings${NC}"
    else
        echo -e "${RED}✗${NC} backup.config.example not found"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} backup.config already exists"
fi

# Create directories
mkdir -p logs
echo -e "${GREEN}✓${NC} Created logs directory"

# Configure OCI CLI if not configured
echo
echo -e "${BLUE}Checking OCI CLI configuration...${NC}"
if [[ ! -f "$HOME/.oci/config" ]]; then
    echo -e "${YELLOW}OCI CLI is not configured.${NC}"
    read -p "Would you like to configure it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oci setup config
    else
        echo -e "${YELLOW}Remember to configure OCI CLI before running backups:${NC}"
        echo "  oci setup config"
    fi
else
    echo -e "${GREEN}✓${NC} OCI CLI is configured"
fi

# Test OCI connection
echo
echo -e "${BLUE}Testing OCI connection...${NC}"
if oci iam region list &> /dev/null; then
    echo -e "${GREEN}✓${NC} Successfully connected to OCI"
else
    echo -e "${YELLOW}⚠${NC} Could not connect to OCI. Please check your configuration."
fi

# Setup cron job
echo
echo -e "${BLUE}Cron job setup${NC}"
echo "To schedule automatic backups, add one of these to your crontab:"
echo "  (Run 'crontab -e' to edit)"
echo
echo "  # Daily at 2 AM:"
echo "  0 2 * * * $(pwd)/backup.sh"
echo
echo "  # Weekly on Sunday at 2 AM:"
echo "  0 2 * * 0 $(pwd)/backup.sh"
echo
echo "  # Monthly on the 1st at 2 AM:"
echo "  0 2 1 * * $(pwd)/backup.sh"
echo

read -p "Would you like to setup a cron job now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Select schedule:"
    echo "1) Daily at 2 AM"
    echo "2) Weekly on Sunday at 2 AM"
    echo "3) Monthly on the 1st at 2 AM"
    echo "4) Custom"
    read -p "Choice (1-4): " SCHEDULE_CHOICE
    
    case $SCHEDULE_CHOICE in
        1)
            CRON_SCHEDULE="0 2 * * *"
            ;;
        2)
            CRON_SCHEDULE="0 2 * * 0"
            ;;
        3)
            CRON_SCHEDULE="0 2 1 * *"
            ;;
        4)
            read -p "Enter custom cron schedule: " CRON_SCHEDULE
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            CRON_SCHEDULE=""
            ;;
    esac
    
    if [[ -n "$CRON_SCHEDULE" ]]; then
        # Add to crontab
        (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $(pwd)/backup.sh >> $(pwd)/logs/cron.log 2>&1") | crontab -
        echo -e "${GREEN}✓${NC} Cron job added: $CRON_SCHEDULE"
    fi
fi

# Create test script
cat > test-backup.sh << 'EOF'
#!/bin/bash
# Test backup script - runs a dry-run backup

echo "Running test backup (dry-run mode)..."
./backup.sh --dry-run --verbose

if [[ $? -eq 0 ]]; then
    echo -e "\033[0;32mTest successful! The backup script is ready to use.\033[0m"
else
    echo -e "\033[0;31mTest failed. Please check the configuration.\033[0m"
fi
EOF

chmod +x test-backup.sh
echo -e "${GREEN}✓${NC} Created test-backup.sh"

echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo "Next steps:"
echo "1. Edit backup.config with your settings"
echo "2. Run ./test-backup.sh to test the configuration"
echo "3. Run ./backup.sh to perform a real backup"
echo
echo "For help, run: ./backup.sh --help"
echo