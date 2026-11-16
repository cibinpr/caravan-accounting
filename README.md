# Caravan Accounting: Income & Expense Management System

A modern, secure rebuild of the Caravan Accounting ERP application built with a **React.js SPA** (Vite + TanStack Query) frontend and a **PHP 8 REST API** (pure PHP, PDO prepared statements) backend with **MySQL / MariaDB**.

---

## 🏗️ Architecture & Project Structure

```text
.
├── api/                       # PHP 8 REST API (Base: /api/v1)
│   ├── app/
│   │   ├── Controllers/       # AuthController, HealthController, etc.
│   │   ├── Core/              # Request, Response, Auth, Audit, Router
│   │   └── Middleware/        # AuthMiddleware, RoleMiddleware, CsrfMiddleware
│   ├── bin/                   # CLI scripts (create_admin.php)
│   ├── config/                # Database PDO connection & Environment Config
│   ├── public/                # Front controller (index.php, .htaccess)
│   └── routes/                # api.php route definitions
├── frontend/                  # React 18 SPA (Vite)
│   ├── src/
│   │   ├── api/               # API client with automatic CSRF & session handling
│   │   ├── components/        # AppLayout, ErrorBoundary, ProtectedRoute, Skeletons
│   │   ├── context/           # AuthContext, ThemeContext
│   │   ├── pages/             # LoginPage, DashboardPage, Placeholders
│   │   ├── styles/            # Accessible theme.css (WCAG 2.1 AA, Light & Dark)
│   │   └── utils/             # Indian Rupee & date formatting utilities
│   ├── index.html
│   ├── package.json
│   └── vite.config.js
├── sql/                       # Database scripts
│   ├── schema.sql             # MariaDB / MySQL 8.0 DDL with strict FKs & indexes
│   └── seed.sql               # Default business categories & migration record
├── storage/                   # Kept outside public web root (FR-BILL-3, NFR-SEC-7)
│   ├── bills/                 # Secure private storage for uploaded receipt files
│   └── logs/                  # Secure application & PHP error logs
├── .env.example               # Environment variables template
├── CARAVAN_SRS.md             # Complete Software Requirements Specification
└── README.md
```

---

## 🚀 Quickstart: Local Development Setup

### 1. Prerequisites
- **Node.js** 18+ & **npm**
- **PHP** 8.1+ with `pdo_mysql`, `mbstring`, `fileinfo`
- **MySQL** 5.7+ or **MariaDB** 10.6+

### 2. Database Initialization
Create your local database and import the schema and default seed data:
```bash
mysql -u root -p -e "CREATE DATABASE caravan_accounting CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p caravan_accounting < sql/schema.sql
mysql -u root -p caravan_accounting < sql/seed.sql
```

### 3. Environment Configuration
Copy `.env.example` to `.env` and configure your database credentials:
```bash
cp .env.example .env
```

### 4. Create Initial Administrator Account
Per SRS Section 8.4, no default passwords are shipped. Use the CLI tool:
```bash
php api/bin/create_admin.php "Administrator" "admin@caravan.local" "YourSecurePassword123"
```

### 5. Running the Backend API
Start the PHP built-in server pointing to `api/public/`:
```bash
php -S 127.0.0.1:8000 -t api/public
```
Verify the health endpoint in your browser or curl:
```bash
curl http://127.0.0.1:8000/api/v1/health
```

### 6. Running the Frontend SPA
In a separate terminal:
```bash
cd frontend
npm install
npm run dev
```
Open [http://localhost:5173](http://localhost:5173) in your browser.

---

## 🛡️ Security Features Implemented (Phase 1)
- **Zero Plaintext Credentials:** Database passwords and application keys stored strictly in `.env` outside the web root (NFR-SEC-6).
- **Hardened Authentication:** Passwords hashed with `Argon2id` / `bcrypt` (`cost: 12`) (FR-AUTH-2).
- **Session Protection:** Session cookies configured with `HttpOnly`, `SameSite=Lax`, and `Secure` (FR-AUTH-3). Automatic session regeneration on login prevents session fixation.
- **Inactivity Timeout:** Server-side 30-minute inactivity auto-logout (FR-AUTH-7).
- **Brute-Force Lockout:** Account/IP locked for 15 minutes after 5 consecutive failed attempts (FR-AUTH-5).
- **CSRF Token Validation:** Validated via `X-CSRF-Token` header on all mutating requests (`POST`, `PUT`, `PATCH`, `DELETE`) (NFR-SEC-3).
- **Immutable Audit Logging:** Every login, failed attempt, and password change recorded in `audit_log` (FR-AUD-1).
- **Private Bill Storage:** `storage/bills/` is placed outside the web root with `.htaccess` deny rules, served only through authenticated streaming endpoints (FR-BILL-3, FR-BILL-4).

---

## 🎨 UI & Readability (WCAG 2.1 AA)
- **Visual Hierarchy:** Metric cards > Profit/Loss banner > Visual breakdowns > Recent Transactions table (UI-D1).
- **Typography Standards:** Base font $\ge 16\text{px}$, summary numbers $\ge 24\text{px}$ bold (UI-D2).
- **Currency & Date Formatting:** Indian numbering grouping (`₹ 1,25,000.00`) and standard `DD-MM-YYYY` dates (UI-D3, Section 2.6).
- **Color Independence:** Income and expense use `+` / `-` symbols and icons, not color alone (UI-D4).
- **Reliability:** Independent widget loading with animated skeleton loaders and retry handlers (UI-D9, UI-D10, UI-D11).
- **Light & Dark Themes:** Built-in theme switcher with user persistence (UI-5).

---

## 📦 Production VPS Deployment Guide (Ubuntu 22.04 / 24.04 LTS)

### Directory Layout on VPS
```text
/var/www/caravan/
  releases/
    20261116-1530/          # Deployment archive
      api/
      frontend/dist/
  current -> releases/20261116-1530   # Atomic symlink switch
  shared/
    .env                    # chmod 600
    storage/bills/          # Persistent uploads
    storage/logs/           # Persistent logs
```

### Nginx Configuration Template
```nginx
server {
    listen 80;
    server_name accounts.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name accounts.example.com;

    ssl_certificate /etc/letsencrypt/live/accounts.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/accounts.example.com/privkey.pem;

    root /var/www/caravan/current/frontend/dist;
    index index.html;

    client_max_body_size 6M;

    # Security Headers (NFR-SEC-5)
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # React SPA Routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # PHP-FPM API Proxy
    location /api/ {
        alias /var/www/caravan/current/api/public/;
        try_files $uri $uri/ @api;

        location ~ \.php$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME /var/www/caravan/current/api/public/index.php;
            fastcgi_pass unix:/run/php/php8.2-fpm.sock;
            fastcgi_intercept_errors on;
        }
    }

    location @api {
        rewrite ^/api/(.*)$ /api/index.php last;
    }

    # Deny dotfiles and private directories
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

---

## 📅 Roadmap / Delivery Status

- [x] **Phase 1: Foundation (Completed)**
  - Database schema & seed data
  - PHP 8 REST API core, PDO, session & CSRF, Auth controller
  - React SPA with Vite, TanStack Query, Theme provider, Auth context, Dashboard layout & UI-D1..D15 metrics
- [x] **Phase 2: Core (Completed)**
  - Income & Expense transaction forms with validation & bill attachments (FR-TXN-1 to FR-TXN-7)
  - Category management (CRUD, in-use protection, inline creation - FR-CAT-1 to FR-CAT-6)
  - Paginated, filterable transaction list views with URL query sync & totals (FR-LST-1 to FR-LST-7)
  - Authenticated bill streaming & modal viewer for JPG, PNG, and PDF (FR-BILL-1 to FR-BILL-5)
- [x] **Phase 3: Insight (Completed)**
  - Interactive monthly cash flow grouped bar chart & category breakdown (FR-DSH-4, FR-DSH-5, UI-D5, UI-D6)
  - Date-ordered Ledger with historical opening balance & running balance calculation (FR-LED-1 to FR-LED-3)
  - Monthly, custom range, and 12-month yearly reports with category share percentages (FR-RPT-1 to FR-RPT-4)
  - CSV & printable PDF statements with company branding (FR-LED-4, FR-RPT-5, FR-RPT-6)
- [x] **Phase 4: Administration (Completed)**
  - User management with Admin/Viewer roles, password reset, and last-admin demote protection (FR-USR-1 to FR-USR-4)
  - Read-only audit log trail with actor, action, entity, and state diff inspection (FR-AUD-1, FR-AUD-2)
  - Strict RBAC enforcement at API and UI navigation levels (FR-RBAC-1 to FR-RBAC-3)
- [x] **Phase 5: Migration & Hardening (Completed)**
  - Idempotent migration script (`sql/migrate_old_data.php`) for legacy tables and 540+ bill receipts (FR-MIG-1 to FR-MIG-6)
  - Automatic category deduplication and missing bill exception handling
  - Mathematical before-and-after reconciliation summary report
  - OWASP Top 10 security review & header hardening
- [x] **Phase 6: Release & Deployment (Completed)**
  - Automated Ubuntu VPS setup script (`deployment/setup_server.sh`) with UFW, Fail2ban, Nginx, PHP-FPM, and MariaDB (DEP-1 to DEP-4)
  - Zero-downtime atomic deployment script (`deployment/deploy.sh`) with pre-release backup and automated release pruning (DEP-5, DEP-8)
  - Sub-5-minute rollback script (`deployment/rollback.sh`) (DEP-5)
  - Scheduled backup automation (`deployment/backup.sh`) with 30-day retention & offsite sync (DEP-7)
  - Automated deployment verification suite (`deployment/verify.sh`) for the Section 8.12 checklist
  - GitHub Actions CI/CD workflow (`.github/workflows/deploy.yml`)
#   c a r a v a n - a c c o u n t i n g  
 