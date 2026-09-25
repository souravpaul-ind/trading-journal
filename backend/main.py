from fastapi import FastAPI, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import io
import csv
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

from database import (
    init_db, get_trades, update_note,
    update_exit_price, delete_all_trades,
    group_fills_into_trades, add_grouped_trade,
    supabase, TABLE
)
from delta_client import fetch_all_filled_orders

app = FastAPI(title="Trading Journal")

init_db()


class NoteUpdate(BaseModel):
    note: str


class ExitUpdate(BaseModel):
    exit_price: float


@app.get("/api/trades")
def list_trades(date: Optional[str] = Query(None)):
    all_trades = get_trades()
    if date:
        all_trades = [
            t for t in all_trades
            if (t.get("trade_time") or "").startswith(date)
        ]
    return all_trades


@app.post("/api/sync")
async def sync_orders():
    fills = await fetch_all_filled_orders()
    grouped = group_fills_into_trades(fills)
    synced = 0
    for trade in grouped:
        try:
            if add_grouped_trade(trade):
                synced += 1
        except Exception as e:
            print(f"Trade skip: {e}")
    return {"synced": synced, "fills": len(fills), "trades": len(grouped)}


@app.put("/api/trades/{trade_id}/note")
def save_note(trade_id: int, body: NoteUpdate):
    update_note(trade_id, body.note)
    return {"ok": True}


@app.put("/api/trades/{trade_id}/exit")
async def save_exit(trade_id: int, body: ExitUpdate):
    import asyncio
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, update_exit_price, trade_id, body.exit_price)
    return {"ok": True}


@app.post("/api/reset")
def reset_trades():
    delete_all_trades()
    return {"ok": True}


@app.get("/api/health")
def health():
    return {"status": "ok"}


# ---------- EXPORT: CSV ----------

@app.get("/api/export/csv")
def export_csv(date: Optional[str] = Query(None)):
    trades = get_trades()
    if date:
        trades = [t for t in trades if (t.get("trade_time") or "").startswith(date)]

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "Date", "Time", "Symbol", "Side", "Size",
        "Entry Price", "Exit Price", "PnL", "Fee", "Funding", "Net PnL", "Note"
    ])

    for t in trades:
        trade_time = t.get("trade_time") or ""
        date_part = trade_time[:10] if trade_time else ""
        time_part = trade_time[11:16] if len(trade_time) > 11 else ""
        pnl = t.get("pnl", 0) or 0
        fee = t.get("fee", 0) or 0
        funding = t.get("funding", 0) or 0
        net_pnl = pnl + funding - fee if t.get("exit_price") else 0

        writer.writerow([
            date_part, time_part,
            t.get("symbol", ""), t.get("side", ""), t.get("size", ""),
            t.get("entry_price", ""), t.get("exit_price", ""),
            pnl, fee, funding, net_pnl, t.get("note", "")
        ])

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename=trades_{date or 'all'}.csv"}
    )


# ---------- EXPORT: EXCEL ----------

@app.get("/api/export/excel")
def export_excel(date: Optional[str] = Query(None)):
    trades = get_trades()
    if date:
        trades = [t for t in trades if (t.get("trade_time") or "").startswith(date)]

    wb = Workbook()
    ws = wb.active
    ws.title = "Trades"

    headers = [
        "Date", "Time", "Symbol", "Side", "Size",
        "Entry Price", "Exit Price", "PnL", "Fee", "Funding", "Net PnL", "Note"
    ]
    ws.append(headers)

    header_fill = PatternFill(start_color="238636", end_color="238636", fill_type="solid")
    header_font = Font(bold=True, color="FFFFFF")
    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")

    for t in trades:
        trade_time = t.get("trade_time") or ""
        date_part = trade_time[:10] if trade_time else ""
        time_part = trade_time[11:16] if len(trade_time) > 11 else ""
        pnl = t.get("pnl", 0) or 0
        fee = t.get("fee", 0) or 0
        funding = t.get("funding", 0) or 0
        net_pnl = pnl + funding - fee if t.get("exit_price") else 0

        ws.append([
            date_part, time_part,
            t.get("symbol", ""), t.get("side", ""), t.get("size", ""),
            t.get("entry_price", ""), t.get("exit_price", ""),
            pnl, fee, funding, net_pnl, t.get("note", "")
        ])

    column_widths = [12, 8, 12, 8, 10, 12, 12, 12, 10, 12, 12, 40]
    for i, width in enumerate(column_widths, start=1):
        ws.column_dimensions[chr(64 + i)].width = width

    net_col = 11
    for row in range(2, len(trades) + 2):
        cell = ws.cell(row=row, column=net_col)
        if cell.value and cell.value < 0:
            cell.font = Font(color="F85149", bold=True)
        elif cell.value and cell.value > 0:
            cell.font = Font(color="3FB950", bold=True)

    output = io.BytesIO()
    wb.save(output)
    output.seek(0)

    return StreamingResponse(
        output,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename=trades_{date or 'all'}.xlsx"}
    )


# ---------- EXPORT: PDF ----------

@app.get("/api/export/pdf")
def export_pdf(date: Optional[str] = Query(None)):
    trades = get_trades()
    if date:
        trades = [t for t in trades if (t.get("trade_time") or "").startswith(date)]

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=A4,
        rightMargin=30, leftMargin=30,
        topMargin=30, bottomMargin=30
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=18,
        textColor=colors.HexColor('#1f6feb'),
        spaceAfter=12,
        alignment=1
    )
    subtitle_style = ParagraphStyle(
        'Subtitle',
        parent=styles['Normal'],
        fontSize=10,
        textColor=colors.HexColor('#8b949e'),
        spaceAfter=20,
        alignment=1
    )

    elements = []

    # Title
    elements.append(Paragraph("Trading Journal", title_style))
    date_range = f"Date: {date}" if date else "All Trades"
    elements.append(Paragraph(date_range, subtitle_style))
    elements.append(Spacer(1, 10))

    # Summary
    closed_trades = [t for t in trades if t.get("exit_price")]
    total_pnl = sum((t.get("pnl", 0) or 0) + (t.get("funding", 0) or 0) - (t.get("fee", 0) or 0) for t in closed_trades)
    total_fee = sum(t.get("fee", 0) or 0 for t in trades)
    total_funding = sum(t.get("funding", 0) or 0 for t in trades)
    wins = sum(1 for t in closed_trades if ((t.get("pnl", 0) or 0) + (t.get("funding", 0) or 0) - (t.get("fee", 0) or 0)) > 0)
    win_rate = (wins / len(closed_trades) * 100) if closed_trades else 0

    summary_data = [
        ["Total Trades", "Closed Trades", "Net PnL", "Total Fee", "Funding", "Win Rate"],
        [str(len(trades)), str(len(closed_trades)), f"${total_pnl:.2f}", f"${total_fee:.4f}", f"${total_funding:.4f}", f"{win_rate:.1f}%"]
    ]
    summary_table = Table(summary_data, colWidths=[80, 80, 80, 80, 80, 80])
    summary_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#161b22')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.HexColor('#f0f6fc')),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('BACKGROUND', (0, 1), (-1, 1), colors.HexColor('#0d1117')),
        ('TEXTCOLOR', (0, 1), (-1, 1), colors.HexColor('#c9d1d9')),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#30363d')),
    ]))
    elements.append(summary_table)
    elements.append(Spacer(1, 20))

    # Trades table
    table_data = [["Date", "Symbol", "Side", "Size", "Entry", "Exit", "PnL", "Fee", "Net"]]

    for t in trades[:200]:  # Limit 200 for PDF size
        trade_time = t.get("trade_time") or ""
        date_part = trade_time[:10] if trade_time else ""
        pnl = t.get("pnl", 0) or 0
        fee = t.get("fee", 0) or 0
        funding = t.get("funding", 0) or 0
        net_pnl = (pnl + funding - fee) if t.get("exit_price") else 0

        table_data.append([
            date_part,
            t.get("symbol", ""),
            t.get("side", "").upper(),
            str(t.get("size", "")),
            f"${t.get('entry_price', '')}",
            f"${t.get('exit_price', '')}" if t.get('exit_price') else "-",
            f"${pnl:.4f}",
            f"${fee:.4f}",
            f"${net_pnl:.4f}" if t.get("exit_price") else "-"
        ])

    if table_data:
        col_widths = [60, 60, 40, 30, 60, 60, 60, 60, 60]
        trade_table = Table(table_data, colWidths=col_widths, repeatRows=1)
        trade_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1f6feb')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 7),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
            ('TOPPADDING', (0, 0), (-1, -1), 4),
            ('BACKGROUND', (0, 1), (-1, -1), colors.HexColor('#f6f8fa')),
            ('TEXTCOLOR', (0, 1), (-1, -1), colors.HexColor('#0d1117')),
            ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor('#8b949e')),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f6f8fa')]),
        ]))
        elements.append(trade_table)

    doc.build(elements)
    buffer.seek(0)

    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=trades_{date or 'all'}.pdf"}
    )


app.mount("/", StaticFiles(directory="../frontend", html=True), name="frontend")
