#!/usr/bin/env bash
# ==============================================================================
# Caravan Accounting - One-Time Ubuntu VPS Setup Script (SRS Section 8.4)
# Target OS: Ubuntu 22.04 / 24.04 LTS
# Usage: sudo bash setup_server.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
  log_error "Please run this setup script as root (sudo bash setup_server.sh)"
  exit 1
fi

log_info "Starting Caravan Accounting VPS Provisioning..."

# 1. Update Packages & Install System Dependencies
log_info "1. Updating APT repositories and upgrading system packages..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y \
  curl \
  wget \
  git \
  unzip \
  ufw \
  fail2ban \
  logrotate \
  ca-certificates \
  software-properties-common

# 2. Configure Firewall (UFW)
log_info "2. Configuring UFW firewall (Ports 22, 80, 443 only)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
log_success "Firewall enabled."

# 3. Install Nginx & MariaDB
log_info "3. Installing Nginx and MariaDB Server..."
apt-get install -y nginx mariadb-server certbot python3-certbot-nginx
systemctl enable nginx
systemctl start nginx
systemctl enable mariadb
systemctl start mariadb

# 4. Install PHP 8 and Required Extensions (SRS Section 2.7 & 8.4)
log_info "4. Installing PHP-FPM and extensions (pdo_mysql, mbstring, fileinfo, zip, opcache)..."
# Add ondrej/php PPA if not on 8.2+
if ! command -v php8.2 &> /dev/null && ! command -v php8.3 &> /dev/null; then
  add-apt-repository -y ppa:ondrej/php || true
  apt-get update -y
fi

# Detect installed or default PHP version
PHP_PKG="php-fpm"
if apt-cache show php8.3-fpm &> /dev/null; then
  PHP_VER="8.3"
elif apt-cache show php8.2-fpm &> /dev/null; then
  PHP_VER="8.2"
else
  PHP_VER="8.1"
fi

log_info "Selected PHP version: ${PHP_VER}"
apt-get install -y \
  php${PHP_VER}-fpm \
  php${PHP_VER}-cli \
  php${PHP_VER}-mysql \
  php${PHP_VER}-mbstring \
  php${PHP_VER}-xml \
  php${PHP_VER}-curl \
  php${PHP_VER}-zip \
  php${PHP_VER}-opcache

systemctl enable php${PHP_VER}-fpm
systemctl start php${PHP_VER}-fpm

# 5. Create Caravan Folder Architecture (SRS Section 8.3)
log_info "5. Setting up /var/www/caravan directory structure..."
APP_DIR="/var/www/caravan"
mkdir -p "${APP_DIR}/releases"
mkdir -p "${APP_DIR}/shared/storage/bills"
mkdir -p "${APP_DIR}/shared/storage/logs"
mkdir -p "${APP_DIR}/backups"

# Create non-root deploy user if not present
if ! id "deploy" &>/dev/null; then
  log_info "Creating 'deploy' system user..."
  useradd -m -s /bin/bash deploy
  usermod -aG www-data deploy
fi

# Permissions: code owned by deploy, writable storage owned by www-data
chown -R deploy:www-data "${APP_DIR}"
chmod -R 755 "${APP_DIR}"
chmod -R 770 "${APP_DIR}/shared/storage"
chown -R www-data:www-data "${APP_DIR}/shared/storage"

log_success "Directory layout configured at ${APP_DIR}."

# 6. Database Provisioning
log_info "6. Configuring MariaDB database and user..."
DB_NAME="caravan_accounting"
DB_USER="caravan_user"
DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)

mariadb -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mariadb -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';"
mariadb -e "FLUSH PRIVILEGES;"

log_success "Database '${DB_NAME}' created."

# 7. Generate Initial .env in shared/ (chmod 600, SRS DEP-6)
ENV_FILE="${APP_DIR}/shared/.env"
if [ ! -f "${ENV_FILE}" ]; then
  log_info "Creating ${ENV_FILE} with secure permissions (chmod 600)..."
  cat > "${ENV_FILE}" <<EOF
APP_NAME="Caravan Accounting"
APP_ENV="production"
APP_DEBUG=false
APP_URL="https://localhost"
APP_TIMEZONE="Asia/Kolkata"

DB_HOST="127.0.0.1"
DB_PORT=3306
DB_DATABASE="${DB_NAME}"
DB_USERNAME="${DB_USER}"
DB_PASSWORD="${DB_PASS}"

SESSION_LIFETIME_MINUTES=30
COOKIE_SECURE=true
COOKIE_SAMESITE="Lax"
MAX_LOGIN_ATTEMPTS=5
LOCKOUT_MINUTES=15

STORAGE_PATH="/var/www/caravan/shared/storage"
MAX_BILL_FILE_SIZE_MB=5
ALLOWED_BILL_MIMES="image/jpeg,image/png,application/pdf"

COMPANY_NAME="Caravan Accounting"
COMPANY_CURRENCY="INR"
COMPANY_CURRENCY_SYMBOL="₹"
EOF
  chown deploy:www-data "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  log_success "${ENV_FILE} created with chmod 600."
fi

# 8. Configure Fail2ban for SSH and Nginx
log_info "8. Hardening Fail2ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 22

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
EOF
systemctl restart fail2ban

echo ""
echo "=============================================================================="
log_success "Caravan Accounting VPS Initial Provisioning Completed!"
echo "=============================================================================="
echo -e "Database Name:     ${GREEN}${DB_NAME}${NC}"
echo -e "Database User:     ${GREEN}${DB_USER}${NC}"
echo -e "Database Password: ${YELLOW}${DB_PASS}${NC} (Saved in ${ENV_FILE})"
echo -e "PHP Version:       ${GREEN}${PHP_VER}${NC}"
echo -e "Web Root Layout:   ${GREEN}${APP_DIR}${NC}"
echo ""
echo "Next Steps:"
echo "1. Point your domain DNS A-record to this VPS IP address."
echo "2. Copy deployment/nginx.conf to /etc/nginx/sites-available/caravan."
echo "3. Obtain SSL cert: certbot --nginx -d yourdomain.com"
echo "4. Deploy your first release using: bash deployment/deploy.sh"
echo "=============================================================================="
