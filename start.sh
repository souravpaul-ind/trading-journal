#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────────
#  Trading Journal - Server Starter
# ─────────────────────────────────────────────

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Banner
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║      📊 TRADING JOURNAL SERVER       ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────────────
#  Step 1: Check if we're in the right folder
# ─────────────────────────────────────────────
if [ ! -d "backend" ]; then
    echo -e "${RED}✗ Error: 'backend' folder not found.${NC}"
    echo -e "${YELLOW}  Make sure you run this script from the project root folder.${NC}"
    echo -e "${YELLOW}  Current folder: $(pwd)${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
#  Step 2: Check .env file
# ─────────────────────────────────────────────
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠ Warning: '.env' file not found in root folder.${NC}"
    echo -e "${YELLOW}  API keys ke bina Sync kaam nahi karega.${NC}"
    echo ""
else
    echo -e "${GREEN}✓ .env file found${NC}"
fi

# ─────────────────────────────────────────────
#  Step 3: Install dependencies (only if missing)
# ─────────────────────────────────────────────
echo -e "${BLUE}ℹ Checking dependencies...${NC}"

MISSING=0
for pkg in fastapi uvicorn httpx dotenv supabase openpyxl; do
    if ! python3.13 -c "import $pkg" 2>/dev/null; then
        python3.13 -m pip install "$pkg" --quiet
        MISSING=1
    fi
done

if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}✓ All dependencies installed${NC}"
fi

# ─────────────────────────────────────────────
#  Step 4: Go into backend folder
# ─────────────────────────────────────────────
cd backend || {
    echo -e "${RED}✗ Failed to enter backend folder.${NC}"
    exit 1
}

# ─────────────────────────────────────────────
#  Step 5: Check main.py exists
# ─────────────────────────────────────────────
if [ ! -f "main.py" ]; then
    echo -e "${RED}✗ Error: 'main.py' not found inside backend folder.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
#  Step 6: Start the server
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ All set! Starting server...${NC}"
echo -e "${CYAN}  ┌─────────────────────────────────────┐${NC}"
echo -e "${CYAN}  │  🌐 Open: http://localhost:8000     │${NC}"
echo -e "${CYAN}  │  ⏹  Stop: Press Ctrl + C            │${NC}"
echo -e "${CYAN}  └─────────────────────────────────────┘${NC}"
echo ""

python3.13 -m uvicorn main:app --host 127.0.0.1 --port 8000
