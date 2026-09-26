```markdown
# 📊 Trading Journal

A personal trading journal for **Delta Exchange India** with automatic sync, PnL tracking, and a beautiful dashboard.

![Status](https://img.shields.io/badge/Status-Active-success)
![Python](https://img.shields.io/badge/Python-3.11+-blue)
![FastAPI](https://img.shields.io/badge/FastAPI-Latest-009688)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## ✨ Features

- 🔄 **Auto-Sync** — Automatically fetches trades from Delta Exchange every 10 minutes
- 📈 **Auto PnL Calculation** — Calculates PnL from entry and exit prices
- 💰 **Fees & Funding Tracking** — Tracks fees and funding from both sides
- 📊 **Beautiful Dashboard** — Today/Week/Month/All-time PnL summary
- 📉 **7-Day Chart** — Visual chart of the last 7 days PnL
- 📝 **Trade Notes** — Write mistakes and learnings for every trade
- 📅 **Date Filter** — View trades for any specific day
- 📥 **Export Options** — Download as CSV, Excel, or PDF
- ⏳ **Open Positions** — Track currently running trades
- 🔐 **Login System** — bcrypt password + 90-day session
- 🌙 **Glassmorphism UI** — Beautiful, modern dark theme
- 📱 **Mobile Responsive** — Perfect on phones too

---

## 🏗️ Tech Stack

| Layer | Technology |
|---|---|
| **Backend** | FastAPI, Python 3.11+ |
| **Database** | Supabase (PostgreSQL) |
| **Frontend** | HTML, CSS, JavaScript |
| **API** | Delta Exchange India REST API |
| **Hosting** | AWS EC2 (or any Linux server) |
| **HTTPS** | Tailscale Funnel |
| **Auto-Sync** | Cron job (every 10 minutes) |

---

## 📁 Project Structure

```
trading-journal/
├── backend/
│   ├── main.py              # FastAPI app + endpoints
│   ├── database.py          # Supabase operations
│   ├── delta_client.py      # Delta Exchange API client
│   └── sync_cron.py         # Auto-sync script (cron job)
├── frontend/
│   └── index.html           # Single-page app
├── deploy.sh                # Universal deploy script
├── requirements.txt         # Python dependencies
├── audit.log                # Audit log (git-ignored)
├── sync.log                 # Sync log (git-ignored)
├── .env                     # API keys (git-ignored)
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start

### Prerequisites

- Python 3.11+
- Delta Exchange India account with API key
- Supabase account (free tier)
- Linux/Mac/Windows

### 1. Clone the Repository

```bash
git clone https://github.com/souravpaul-ind/trading-journal.git
cd trading-journal
```

### 2. Create `.env` File

```bash
nano .env
```

Add these lines:

```env
DELTA_API_KEY=your_delta_api_key
DELTA_API_SECRET=your_delta_api_secret
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_KEY=your_service_role_key
API_KEY=your_random_api_key
LOGIN_USER=admin
LOGIN_PASS_HASH=your_bcrypt_hash
```

### 3. Deploy with One Command

```bash
bash deploy.sh
```

A menu will appear — select your OS:

```
  1) Ubuntu / Debian (Linux server)
  2) Other Linux (Fedora, Arch, etc.)
  3) macOS
  4) Windows (Git Bash / WSL)
  5) Windows (Native - Manual instructions)
```

**That's it!** The deploy script will:
- Install dependencies
- Create virtual environment
- Set up systemd service
- Add auto-sync cron job
- Set up Tailscale Funnel
- Start the server

---

## 🔧 Setup Details

### Delta Exchange India API Key

1. Log in to [india.delta.exchange](https://india.delta.exchange)
2. Go to **AlgoHub → APIs**
3. Click **Create New API Key**
4. **Permissions:** Enable `Read Data`
5. **IP Whitelist:** Add your server's **Elastic IP**
6. **Copy** the Key and Secret

### Supabase Setup

1. Create an account at [supabase.com](https://supabase.com)
2. Create a **New Project**
3. In **Table Editor**, create a `trades` table:

| Column | Type | Notes |
|---|---|---|
| `id` | int8 | Primary key, auto-increment |
| `delta_order_id` | text | UNIQUE |
| `symbol` | text | |
| `side` | text | |
| `size` | float8 | |
| `entry_price` | float8 | |
| `exit_price` | float8 | Nullable |
| `pnl` | float8 | |
| `fee` | float8 | |
| `funding` | float8 | |
| `trade_time` | timestamptz | Nullable |
| `note` | text | |

4. **Disable RLS** (or create a policy)
5. Copy the **Project URL** and **service_role key**

### Generate Password Hash

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'YOUR_PASSWORD', bcrypt.gensalt()).decode())"
```

Put this output in `.env` as `LOGIN_PASS_HASH`.

---

## 📡 API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/trades` | All trades (optional `?date=YYYY-MM-DD`) |
| POST | `/api/sync` | Sync trades + positions from Delta |
| PUT | `/api/trades/{id}/note` | Update trade note |
| PUT | `/api/trades/{id}/exit` | Update exit price (auto PnL) |
| GET | `/api/export/csv` | Download CSV |
| GET | `/api/export/excel` | Download Excel |
| GET | `/api/export/pdf` | Download PDF |
| GET | `/api/health` | Health check |

---

## ⏰ Auto-Sync

### Linux (Cron Job)

Automatically set up during deployment:

```bash
# Every 10 minutes
*/10 * * * * cd /home/ubuntu/trading-journal/backend && /home/ubuntu/trading-journal/venv/bin/python3 sync_cron.py >> /home/ubuntu/trading-journal/sync.log 2>&1
```

**Verify:**

```bash
crontab -l
```

**Logs:**

```bash
tail -f ~/trading-journal/sync.log
```

### Windows (Task Scheduler)

1. Open **Task Scheduler** (`taskschd.msc`)
2. **Create Basic Task**
3. Name: `Trading Journal Sync`
4. Trigger: **Daily, repeat every 10 minutes**
5. Action: **Start a program**
   - Program: `venv\Scripts\python.exe`
   - Arguments: `sync_cron.py`
   - Start in: `trading-journal\backend`

---

## 🎛️ Management Commands

Manage everything through the deploy script:

```bash
bash deploy.sh
```

| Option | Description |
|---|---|
| **6** | Check service + cron status |
| **7** | Restart service |
| **8** | Stop service |
| **9** | View live logs |
| **10** | Uninstall (keep files) |
| **11** | Full uninstall (delete everything) |

### Manual Commands

```bash
# Service status
sudo systemctl status journal

# Restart
sudo systemctl restart journal

# Stop
sudo systemctl stop journal

# Live logs
sudo journalctl -u journal -f

# Cron logs
tail -f ~/trading-journal/sync.log

# Audit logs
tail -f ~/trading-journal/audit.log
```

---

## 🔐 Security Features

| Feature | Status |
|---|---|
| **HTTPS** | ✅ Tailscale Funnel |
| **Login (bcrypt)** | ✅ |
| **Session (90 days)** | ✅ |
| **Logout** | ✅ |
| **Audit Log** | ✅ |
| **HTTPS Redirect** | ✅ |
| **Firewall (UFW)** | ✅ |
| **Fail2Ban** | ✅ |
| **Rate Limiting** | ✅ |
| **Security Headers** | ✅ |
| **CORS** | ✅ |
| **Delta Read-only Key** | ✅ |

---

## 🖥️ Hosting Options

| Provider | Cost | Notes |
|---|---|---|
| **AWS EC2** | Free (12 months) | Best for IP whitelist |
| **DigitalOcean** | $6/month | Simple setup |
| **Vultr / Linode** | $5-6/month | Good alternatives |
| **Oracle Cloud** | Always free | 1 static IP free |
| **Render** | Free tier | IP whitelist issue |

**Recommended:** AWS EC2 with **Elastic IP** (for Delta's IP whitelist)

---

## 🐛 Troubleshooting

### Service won't start

```bash
sudo journalctl -u journal -n 50
```

### Sync not working

```bash
# Check cron
crontab -l

# Check logs
tail -50 ~/trading-journal/sync.log

# Manual test
cd ~/trading-journal/backend
source ~/trading-journal/venv/bin/activate
python3 sync_cron.py
```

### Login not working

```bash
# Check audit log
tail -20 ~/trading-journal/audit.log

# Verify .env
cat ~/trading-journal/.env
```

### API errors

- **401 Unauthorized** → Login session expired
- **404 Not Found** → Wrong endpoint
- **500 Error** → Supabase connection issue

---

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first.

---

## 📝 License

MIT License — free to use, modify, distribute.

---

## 🙏 Acknowledgments

- [Delta Exchange India](https://india.delta.exchange) — Trading API
- [Supabase](https://supabase.com) — Database
- [FastAPI](https://fastapi.tiangolo.com) — Backend framework
- [Tailscale](https://tailscale.com) — HTTPS tunnel

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/souravpaul-ind/trading-journal/issues)
- **Delta Support:** support@delta.exchange
- **Supabase Docs:** [supabase.com/docs](https://supabase.com/docs)

---

## ⚠️ Disclaimer

This tool is for **personal use**. Trading decisions are **your responsibility**. Always trade at your own risk.

---

**Made with ❤️ for traders**
```
