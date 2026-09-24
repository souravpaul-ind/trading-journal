from fastapi import FastAPI, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import io
import csv
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

from database import init_db, add_trade, get_trades, update_note, update_funding
from delta_client import fetch_all_filled_orders

app = FastAPI(title="Trading Journal")

# Server start hote hi Supabase connection check karta hai
init_db()


# ---------- Request Body Models ----------

class NoteUpdate(BaseModel):
    note: str

class FundingUpdate(BaseModel):
    funding: float


# ---------- API Endpoints ----------

@app.get("/api/trades")
def list_trades(date: Optional[str] = Query(None)):
    """Saare trades Supabase se nikaal kar frontend ko bhejta hai.
    Agar date di gayi hai (YYYY-MM-DD) to sirf us din ke trades."""
    all_trades = get_trades()
    if date:
        all_trades = [
            t for t in all_trades 
            if (t.get("trade_time") or "").startswith(date)
        ]
    return all_trades


@app.post("/api/sync")
async def sync_orders():
    """Delta Exchange se saare filled orders (purane + naye) Supabase mein sync karta hai"""
    orders = await fetch_all_filled_orders()
    synced = 0
    for order in orders:
        try:
            add_trade(order)
            synced += 1
        except Exception as e:
            print(f"Order skip hua: {e}")
    return {"synced": synced, "total_fetched": len(orders)}


@app.put("/api/trades/{trade_id}/note")
def save_note(trade_id: int, body: NoteUpdate):
    """Trade ka note Supabase mein update karta hai"""
    update_note(trade_id, body.note)
    return {"ok": True}


@app.put("/api/trades/{trade_id}/funding")
def save_funding(trade_id: int, body: FundingUpdate):
    """Funding manually update karne ke liye"""
    update_funding(trade_id, body.funding)
    return {"ok": True}


@app.get("/api/health")
def health():
    """Server zinda hai ya nahi check karne ke liye"""
    return {"status": "ok"}


# ---------- Export Endpoints ----------

@app.get("/api/export/csv")
def export_csv(date: Optional[str] = Query(None)):
    """Trades ko CSV file mein export karta hai (Excel mein directly khulti hai)"""
    trades = get_trades()
    
    if date:
        trades = [t for t in trades if (t.get("trade_time") or "").startswith(date)]
    
    output = io.StringIO()
    writer = csv.writer(output)
    
    # Header row
    writer.writerow([
        "Date", "Time", "Symbol", "Side", "Size", 
        "Entry Price", "Exit Price", "PnL", "Fee", "Funding", "Net PnL", "Note"
    ])
    
    # Data rows
    for t in trades:
        trade_time = t.get("trade_time") or ""
        date_part = trade_time[:10] if trade_time else ""
        time_part = trade_time[11:16] if len(trade_time) > 11 else ""
        
        pnl = t.get("pnl", 0) or 0
        fee = t.get("fee", 0) or 0
        funding = t.get("funding", 0) or 0
        net_pnl = pnl - fee - funding
        
        writer.writerow([
            date_part,
            time_part,
            t.get("symbol", ""),
            t.get("side", ""),
            t.get("size", ""),
            t.get("entry_price", ""),
            t.get("exit_price", ""),
            pnl,
            fee,
            funding,
            net_pnl,
            t.get("note", "")
        ])
    
    output.seek(0)
    
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename=trades_{date or 'all'}.csv"
        }
    )


@app.get("/api/export/excel")
def export_excel(date: Optional[str] = Query(None)):
    """Trades ko proper Excel (.xlsx) file mein export karta hai with formatting"""
    trades = get_trades()
    
    if date:
        trades = [t for t in trades if (t.get("trade_time") or "").startswith(date)]
    
    # Excel workbook banao
    wb = Workbook()
    ws = wb.active
    ws.title = "Trades"
    
    # Header row
    headers = [
        "Date", "Time", "Symbol", "Side", "Size", 
        "Entry Price", "Exit Price", "PnL", "Fee", "Funding", "Net PnL", "Note"
    ]
    ws.append(headers)
    
    # Header styling
    header_fill = PatternFill(start_color="238636", end_color="238636", fill_type="solid")
    header_font = Font(bold=True, color="FFFFFF")
    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")
    
    # Data rows
    for t in trades:
        trade_time = t.get("trade_time") or ""
        date_part = trade_time[:10] if trade_time else ""
        time_part = trade_time[11:16] if len(trade_time) > 11 else ""
        
        pnl = t.get("pnl", 0) or 0
        fee = t.get("fee", 0) or 0
        funding = t.get("funding", 0) or 0
        net_pnl = pnl - fee - funding
        
        ws.append([
            date_part,
            time_part,
            t.get("symbol", ""),
            t.get("side", ""),
            t.get("size", ""),
            t.get("entry_price", ""),
            t.get("exit_price", ""),
            pnl,
            fee,
            funding,
            net_pnl,
            t.get("note", "")
        ])
    
    # Column widths set karo
    column_widths = [12, 8, 12, 8, 10, 12, 12, 12, 10, 12, 12, 40]
    for i, width in enumerate(column_widths, start=1):
        ws.column_dimensions[chr(64 + i)].width = width
    
    # Net PnL column ko color karo (green/red)
    net_col = 11  # K column
    for row in range(2, len(trades) + 2):
        cell = ws.cell(row=row, column=net_col)
        if cell.value and cell.value < 0:
            cell.font = Font(color="F85149", bold=True)
        elif cell.value and cell.value > 0:
            cell.font = Font(color="3FB950", bold=True)
    
    # Memory mein save karo
    output = io.BytesIO()
    wb.save(output)
    output.seek(0)
    
    return StreamingResponse(
        output,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename=trades_{date or 'all'}.xlsx"
        }
    )


# ---------- Frontend Serve ----------

app.mount("/", StaticFiles(directory="../frontend", html=True), name="frontend")