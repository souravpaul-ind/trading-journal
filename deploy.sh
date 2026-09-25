#!/bin/bash

# ============================================
# Trading Journal - Universal Deploy Script
# ============================================
# Supports: Linux, Mac, Windows (Git Bash/WSL)
# ============================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
                echo "ubuntu"
            else
                echo "linux"
            fi
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "mac"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

DETECTED_OS=$(detect_os)

# ============================================
# MENU
# ============================================
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗"
    echo "║   TRADING JOURNAL - CONTROL PANEL          ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Detected OS: ${GREEN}$DETECTED_OS${NC}"
    echo ""
    echo -e "${BLUE}─────── DEPLOY ───────${NC}"
    echo "  1) Ubuntu / Debian (Linux server)"
    echo "  2) Other Linux (Fedora, Arch, etc.)"
    echo "  3) macOS"
    echo "  4) Windows (Git Bash / WSL)"
    echo "  5) Windows (Native - Manual instructions)"
    echo ""
    echo -e "${YELLOW}─────── MANAGE ───────${NC}"
    echo "  6) Check Service Status"
    echo "  7) Restart Service"
    echo "  8) Stop Service"
    echo "  9) View Live Logs"
    echo ""
    echo -e "${RED}─────── DANGER ───────${NC}"
    echo " 10) Uninstall (Stop + Remove Service)"
    echo " 11) Full Uninstall (Delete everything)"
    echo ""
    echo "  0) Exit"
    echo ""
    read -p "Enter choice [0-11]: " CHOICE
}

# ============================================
# PROJECT SETUP (Common)
# ============================================
setup_project() {
    if [ ! -d "trading-journal" ]; then
        echo -e "${YELLOW}Cloning repository...${NC}"
        git clone https://github.com/souravpaul-ind/trading-journal.git
    fi
    cd trading-journal
}

# ============================================
# UBUNTU / DEBIAN
# ============================================
deploy_ubuntu() {
    echo -e "${YELLOW}[1/6] Updating system...${NC}"
    sudo apt update -qq
    sudo apt install -y -qq python3 python3-venv python3-pip git

    echo -e "${YELLOW}[2/6] Setting up virtual environment...${NC}"
    [ ! -d "venv" ] && python3 -m venv venv
    source venv/bin/activate

    echo -e "${YELLOW}[3/6] Installing dependencies...${NC}"
    pip install -q --upgrade pip
    pip install -q fastapi uvicorn httpx python-dotenv supabase openpyxl reportlab

    if [ ! -f ".env" ]; then
        echo ""
        echo -e "${RED}ERROR: .env file missing!${NC}"
        echo ""
        echo "Create .env with these lines:"
        echo "  DELTA_API_KEY=your_key"
        echo "  DELTA_API_SECRET=your_secret"
        echo "  SUPABASE_URL=https://xxxx.supabase.co"
        echo "  SUPABASE_KEY=your_anon_key"
        echo ""
        echo "Then run: nano .env"
        exit 1
    fi

    echo -e "${YELLOW}[4/6] Setting up systemd service...${NC}"
    sudo tee /etc/systemd/system/journal.service > /dev/null <<EOF
[Unit]
Description=Trading Journal FastAPI
After=network.target

[Service]
User=$USER
WorkingDirectory=$(pwd)/backend
ExecStart=$(pwd)/venv/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable journal
    sudo systemctl restart journal

    echo -e "${YELLOW}[5/6] Checking status...${NC}"
    sleep 3

    if sudo systemctl is-active --quiet journal; then
        echo -e "${GREEN}[6/6] ✓ Deploy Successful!${NC}"
        show_success
    else
        echo -e "${RED}✗ Deploy Failed! Check logs: sudo journalctl -u journal -n 50${NC}"
        exit 1
    fi
}

# ============================================
# OTHER LINUX
# ============================================
deploy_linux() {
    echo -e "${YELLOW}[1/5] Installing Python and Git...${NC}"
    
    if command -v dnf &> /dev/null; then
        sudo dnf install -y python3 python3-pip git
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm python python-pip git
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y python3 python3-pip git
    else
        echo -e "${RED}Cannot detect package manager!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[2/5] Setting up virtual environment...${NC}"
    [ ! -d "venv" ] && python3 -m venv venv
    source venv/bin/activate

    echo -e "${YELLOW}[3/5] Installing dependencies...${NC}"
    pip install -q --upgrade pip
    pip install -q fastapi uvicorn httpx python-dotenv supabase openpyxl reportlab

    if [ ! -f ".env" ]; then
        echo -e "${RED}ERROR: .env file missing!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[4/5] Starting server...${NC}"
    echo ""
    echo -e "${GREEN}Run this command manually to start server:${NC}"
    echo "  cd $(pwd)/backend"
    echo "  source ../venv/bin/activate"
    echo "  uvicorn main:app --host 0.0.0.0 --port 8000"
    echo ""
}

# ============================================
# macOS
# ============================================
deploy_mac() {
    echo -e "${YELLOW}[1/5] Checking Homebrew...${NC}"
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo -e "${YELLOW}[2/5] Installing Python...${NC}"
    brew install python3 git

    echo -e "${YELLOW}[3/5] Setting up virtual environment...${NC}"
    [ ! -d "venv" ] && python3 -m venv venv
    source venv/bin/activate

    echo -e "${YELLOW}[4/5] Installing dependencies...${NC}"
    pip install -q --upgrade pip
    pip install -q fastapi uvicorn httpx python-dotenv supabase openpyxl reportlab

    if [ ! -f ".env" ]; then
        echo -e "${RED}ERROR: .env file missing!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[5/5] Starting server...${NC}"
    cd backend
    uvicorn main:app --host 0.0.0.0 --port 8000
}

# ============================================
# WINDOWS
# ============================================
deploy_windows() {
    echo -e "${YELLOW}[1/5] Checking Python...${NC}"
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python not found!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[2/5] Setting up virtual environment...${NC}"
    [ ! -d "venv" ] && python3 -m venv venv
    source venv/Scripts/activate 2>/dev/null || source venv/bin/activate

    echo -e "${YELLOW}[3/5] Installing dependencies...${NC}"
    pip install -q --upgrade pip
    pip install -q fastapi uvicorn httpx python-dotenv supabase openpyxl reportlab

    if [ ! -f ".env" ]; then
        echo -e "${RED}ERROR: .env file missing!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[4/5] Starting server...${NC}"
    cd backend
    python -m uvicorn main:app --host 0.0.0.0 --port 8000
}

# ============================================
# WINDOWS NATIVE
# ============================================
deploy_windows_native() {
    echo ""
    echo -e "${CYAN}WINDOWS NATIVE - MANUAL INSTRUCTIONS${NC}"
    echo ""
    echo "Step 1: Install Python 3.12 from https://python.org/downloads"
    echo "  → CHECK 'Add Python to PATH'"
    echo ""
    echo "Step 2: Install Git from https://git-scm.com/download/win"
    echo ""
    echo "Step 3: Open CMD, run:"
    echo "  git clone https://github.com/souravpaul-ind/trading-journal.git"
    echo "  cd trading-journal"
    echo "  python -m venv venv"
    echo "  venv\\Scripts\\activate"
    echo "  pip install fastapi uvicorn httpx python-dotenv supabase openpyxl reportlab"
    echo "  notepad .env"
    echo "  cd backend"
    echo "  python -m uvicorn main:app --host 127.0.0.1 --port 8000"
    echo ""
}

# ============================================
# SERVICE MANAGEMENT
# ============================================
check_status() {
    echo ""
    echo -e "${CYAN}Service Status:${NC}"
    echo ""
    if sudo systemctl is-active --quiet journal; then
        sudo systemctl status journal --no-pager | head -15
    else
        echo -e "${RED}Service is not running.${NC}"
        echo ""
        echo "Check if it's installed:"
        sudo systemctl status journal --no-pager 2>&1 | head -5 || echo "Service not found"
    fi
}

restart_service() {
    echo -e "${YELLOW}Restarting service...${NC}"
    sudo systemctl restart journal
    sleep 2
    if sudo systemctl is-active --quiet journal; then
        echo -e "${GREEN}✓ Service restarted successfully${NC}"
    else
        echo -e "${RED}✗ Service failed to restart${NC}"
        sudo journalctl -u journal -n 20
    fi
}

stop_service() {
    echo ""
    echo -e "${YELLOW}Stopping service...${NC}"
    
    if sudo systemctl is-active --quiet journal; then
        sudo systemctl stop journal
        sleep 1
        if sudo systemctl is-active --quiet journal; then
            echo -e "${RED}✗ Service still running. Forcing stop...${NC}"
            sudo systemctl kill journal
        else
            echo -e "${GREEN}✓ Service stopped successfully${NC}"
        fi
    else
        echo -e "${YELLOW}Service is already stopped.${NC}"
    fi
    echo ""
}

view_logs() {
    echo ""
    echo -e "${CYAN}Live logs (Ctrl+C to exit):${NC}"
    echo ""
    sudo journalctl -u journal -f
}

# ============================================
# UNINSTALL
# ============================================
uninstall_service() {
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════╗"
    echo "║   UNINSTALL - SERVICE ONLY                 ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will:"
    echo "  ✓ Stop the service"
    echo "  ✓ Remove systemd service file"
    echo "  ✓ Keep all project files"
    echo ""
    read -p "Are you sure? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled."
        return
    fi
    
    echo ""
    echo -e "${YELLOW}[1/4] Stopping service...${NC}"
    sudo systemctl stop journal 2>/dev/null || echo "Service not running"
    
    echo -e "${YELLOW}[2/4] Disabling service...${NC}"
    sudo systemctl disable journal 2>/dev/null || echo "Service not enabled"
    
    echo -e "${YELLOW}[3/4] Removing service file...${NC}"
    sudo rm -f /etc/systemd/system/journal.service
    
    echo -e "${YELLOW}[4/4] Reloading systemd...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}✓ Service uninstalled successfully${NC}"
    echo ""
    echo "Project files are still in: $(pwd)"
    echo "To restart, run: bash deploy.sh (option 1)"
    echo ""
}

full_uninstall() {
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════╗"
    echo "║   FULL UNINSTALL - EVERYTHING              ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}WARNING: This will DELETE everything!${NC}"
    echo ""
    echo "This will:"
    echo "  ✓ Stop the service"
    echo "  ✓ Remove systemd service file"
    echo "  ✓ Delete virtual environment"
    echo "  ✓ Delete all project files"
    echo "  ✓ Remove from system"
    echo ""
    echo -e "${RED}THIS CANNOT BE UNDONE!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " CONFIRM
    
    if [ "$CONFIRM" != "DELETE" ]; then
        echo "Cancelled."
        return
    fi
    
    echo ""
    echo -e "${YELLOW}[1/5] Stopping service...${NC}"
    sudo systemctl stop journal 2>/dev/null || echo "Service not running"
    
    echo -e "${YELLOW}[2/5] Disabling service...${NC}"
    sudo systemctl disable journal 2>/dev/null || echo "Service not enabled"
    
    echo -e "${YELLOW}[3/5] Removing service file...${NC}"
    sudo rm -f /etc/systemd/system/journal.service
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    
    echo -e "${YELLOW}[4/5] Finding project directory...${NC}"
    PROJECT_DIR=$(pwd)
    echo "Project directory: $PROJECT_DIR"
    
    echo -e "${YELLOW}[5/5] Deleting project files...${NC}"
    cd ~
    
    # Confirm before deleting
    read -p "Delete '$PROJECT_DIR'? (yes/no): " CONFIRM2
    if [ "$CONFIRM2" == "yes" ]; then
        rm -rf "$PROJECT_DIR"
        echo -e "${GREEN}✓ Project deleted${NC}"
    else
        echo "Project files kept at: $PROJECT_DIR"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Full uninstall complete${NC}"
    echo ""
}

# ============================================
# SUCCESS MESSAGE
# ============================================
show_success() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════╗"
    echo "║   ✓ DEPLOY SUCCESSFUL!                     ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Server running on port 8000"
    echo ""
    echo "Commands:"
    echo "  Status:  sudo systemctl status journal"
    echo "  Logs:    sudo journalctl -u journal -f"
    echo "  Restart: sudo systemctl restart journal"
    echo "  Stop:    sudo systemctl stop journal"
    echo ""
    echo "Next: Open http://YOUR_SERVER_IP:8000"
    echo ""
}

# ============================================
# RUN
# ============================================
show_menu

case $CHOICE in
    1) setup_project; deploy_ubuntu ;;
    2) setup_project; deploy_linux ;;
    3) setup_project; deploy_mac ;;
    4) setup_project; deploy_windows ;;
    5) deploy_windows_native ;;
    6) check_status ;;
    7) restart_service ;;
    8) stop_service ;;
    9) view_logs ;;
    10) uninstall_service ;;
    11) full_uninstall ;;
    0) echo "Exiting..."; exit 0 ;;
    *) echo -e "${RED}Invalid choice!${NC}"; exit 1 ;;
esac
