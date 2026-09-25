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
# AUTO-SYNC CRON SETUP (Called automatically)
# ============================================
setup_cron() {
    echo -e "${YELLOW}Setting up auto-sync cron job (every 10 minutes)...${NC}"
    
    PROJECT_DIR=$(pwd)
    BACKEND_DIR="$PROJECT_DIR/backend"
    VENV_PYTHON="$PROJECT_DIR/venv/bin/python3"
    LOG_FILE="$PROJECT_DIR/sync.log"

    # Purana cron job hatao (agar hai)
    crontab -l 2>/dev/null | grep -v "sync_cron.py" | crontab - 2>/dev/null || true

    # Naya cron job add karo
    (crontab -l 2>/dev/null; echo "*/10 * * * * cd $BACKEND_DIR && $VENV_PYTHON sync_cron.py >> $LOG_FILE 2>&1") | crontab -

    echo -e "${GREEN}  ✓ Cron job added (every 10 minutes)${NC}"
}

# ============================================
# CREATE sync_cron.py (Called automatically)
# ============================================
create_sync_script() {
    if [ ! -f "backend/sync_cron.py" ]; then
        echo -e "${YELLOW}Creating sync_cron.py...${NC}"
        cat > backend/sync_cron.py <<'PYEOF'
#!/usr/bin/env python3
"""Automatic sync script - Cron job ke liye"""
import asyncio
import sys
import os
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from delta_client import fetch_all_filled_orders, fetch_open_positions
from database import (
    group_fills_into_trades, add_grouped_trade,
    add_open_position, remove_closed_open_positions
)


async def auto_sync():
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] Auto-sync started...")
    try:
        fills = await fetch_all_filled_orders()
        grouped = group_fills_into_trades(fills)
        removed = remove_closed_open_positions(grouped)
        synced = 0
        for trade in grouped:
            try:
                if add_grouped_trade(trade):
                    synced += 1
            except Exception as e:
                print(f"  Trade skip: {e}")
        open_positions = await fetch_open_positions()
        open_count = 0
        for pos in open_positions:
            try:
                if add_open_position(pos):
                    open_count += 1
            except Exception as e:
                print(f"  Position skip: {e}")
        print(f"[{timestamp}] Complete: {synced} synced, {open_count} open, {removed} removed")
        return True
    except Exception as e:
        print(f"[{timestamp}] Failed: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    asyncio.run(auto_sync())
PYEOF
        echo -e "${GREEN}  ✓ sync_cron.py created${NC}"
    fi
}

# ============================================
# PROJECT SETUP
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
    echo -e "${YELLOW}[1/7] Updating system...${NC}"
    sudo apt update -qq
    sudo apt install -y -qq python3 python3-venv python3-pip git cron

    echo -e "${YELLOW}[2/7] Setting up virtual environment...${NC}"
    [ ! -d "venv" ] && python3 -m venv venv
    source venv/bin/activate

    echo -e "${YELLOW}[3/7] Installing dependencies...${NC}"
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

    echo -e "${YELLOW}[4/7] Setting up systemd service...${NC}"
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

    # Auto-setup sync script + cron
    create_sync_script
    setup_cron

    echo -e "${YELLOW}[6/7] Checking status...${NC}"
    sleep 3

    if sudo systemctl is-active --quiet journal; then
        echo -e "${GREEN}[7/7] ✓ Deploy Successful!${NC}"
        show_success
        show_cron_info
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
        sudo dnf install -y python3 python3-pip git cronie
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm python python-pip git cronie
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y python3 python3-pip git cron
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

    echo -e "${YELLOW}[4/5] Enabling cron service...${NC}"
    sudo systemctl enable crond 2>/dev/null || sudo systemctl enable cron 2>/dev/null || true
    sudo systemctl start crond 2>/dev/null || sudo systemctl start cron 2>/dev/null || true

    # Auto-setup sync script + cron
    create_sync_script
    setup_cron

    echo -e "${YELLOW}[5/5] Done!${NC}"
    echo ""
    echo "Start server manually:"
    echo "  cd $(pwd)/backend"
    echo "  source ../venv/bin/activate"
    echo "  uvicorn main:app --host 0.0.0.0 --port 8000"
    echo ""
    echo "Auto-sync: every 10 minutes"
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

    # Auto-setup sync script + cron
    create_sync_script
    setup_cron

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

    # Auto-setup sync script
    create_sync_script

    echo -e "${YELLOW}[4/5] Windows Task Scheduler setup...${NC}"
    echo ""
    echo -e "${YELLOW}Windows pe cron nahi hota. Task Scheduler use karo:${NC}"
    echo ""
    echo "1. Open Task Scheduler (taskschd.msc)"
    echo "2. Create Basic Task"
    echo "3. Name: Trading Journal Sync"
    echo "4. Trigger: Daily, repeat every 10 minutes"
    echo "5. Action: Start a program"
    echo "   Program: $(pwd)/venv/Scripts/python.exe"
    echo "   Arguments: sync_cron.py"
    echo "   Start in: $(pwd)/backend"
    echo ""

    echo -e "${YELLOW}[5/5] Starting server...${NC}"
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
    echo "Step 4: Auto-sync setup (Task Scheduler):"
    echo "  → Open taskschd.msc"
    echo "  → Create Basic Task"
    echo "  → Trigger: Daily, repeat every 10 minutes"
    echo "  → Action: python.exe sync_cron.py"
    echo "  → Start in: trading-journal/backend"
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
        sudo systemctl status journal --no-pager 2>&1 | head -5 || echo "Service not found"
    fi
    
    echo ""
    echo -e "${CYAN}Cron Job Status:${NC}"
    echo ""
    crontab -l 2>/dev/null | grep "sync_cron.py" || echo "No cron job found"
    echo ""
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
            sudo systemctl kill journal
        else
            echo -e "${GREEN}✓ Service stopped${NC}"
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
    echo -e "${RED}UNINSTALL - SERVICE ONLY${NC}"
    echo ""
    read -p "Are you sure? (yes/no): " CONFIRM
    [ "$CONFIRM" != "yes" ] && echo "Cancelled." && return
    
    echo -e "${YELLOW}[1/4] Stopping service...${NC}"
    sudo systemctl stop journal 2>/dev/null || echo "Service not running"
    
    echo -e "${YELLOW}[2/4] Removing service + cron...${NC}"
    sudo systemctl disable journal 2>/dev/null || true
    sudo rm -f /etc/systemd/system/journal.service
    crontab -l 2>/dev/null | grep -v "sync_cron.py" | crontab - 2>/dev/null || true
    
    echo -e "${YELLOW}[3/4] Reloading systemd...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    
    echo -e "${YELLOW}[4/4] Done${NC}"
    echo ""
    echo -e "${GREEN}✓ Service + cron uninstalled${NC}"
    echo "Project files still in: $(pwd)"
    echo ""
}

full_uninstall() {
    echo ""
    echo -e "${RED}FULL UNINSTALL - EVERYTHING${NC}"
    echo ""
    echo -e "${RED}WARNING: This will DELETE everything!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " CONFIRM
    [ "$CONFIRM" != "DELETE" ] && echo "Cancelled." && return
    
    echo -e "${YELLOW}[1/4] Stopping service...${NC}"
    sudo systemctl stop journal 2>/dev/null || true
    
    echo -e "${YELLOW}[2/4] Removing service + cron...${NC}"
    sudo systemctl disable journal 2>/dev/null || true
    sudo rm -f /etc/systemd/system/journal.service
    crontab -l 2>/dev/null | grep -v "sync_cron.py" | crontab - 2>/dev/null || true
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    
    echo -e "${YELLOW}[3/4] Project directory:${NC}"
    PROJECT_DIR=$(pwd)
    echo "$PROJECT_DIR"
    
    echo -e "${YELLOW}[4/4] Deleting project files...${NC}"
    cd ~
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
# SUCCESS MESSAGES
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

show_cron_info() {
    echo -e "${CYAN}╔════════════════════════════════════════════╗"
    echo "║   AUTO-SYNC ACTIVE                         ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Auto-sync: Every 10 minutes"
    echo "Logs:      tail -f $(pwd)/sync.log"
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
