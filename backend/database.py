import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv(dotenv_path="../.env")

url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_KEY")
supabase: Client = create_client(url, key)

TABLE = "trades"


def init_db():
    try:
        supabase.table(TABLE).select("id").limit(1).execute()
        print("Supabase connected ✓")
    except Exception as e:
        print(f"Supabase connection error: {e}")


def group_fills_into_trades(fills):
    """Delta ke fills ko match karke trades banata hai.
    Partial closes aur dono side ki fees ko sahi handle karta hai (FIFO matching)."""
    from collections import defaultdict

    by_symbol = defaultdict(list)
    for f in fills:
        symbol = f.get("product_symbol")
        if symbol:
            by_symbol[symbol].append(f)

    trades = []

    for symbol, symbol_fills in by_symbol.items():
        # Time se sort karo (purana pehle)
        symbol_fills.sort(key=lambda x: x.get("created_at", ""))

        # Open positions (jo abhi match nahi hui)
        open_positions = []

        for fill in symbol_fills:
            side = fill.get("side")
            price = float(fill.get("price", 0) or 0)
            size = float(fill.get("size", 0) or 0)
            time = fill.get("created_at")
            fill_id = fill.get("id")
            fee = float(fill.get("commission", 0) or 0)
            funding = float(fill.get("realised_funding", 0) or 0)

            # Opposite position dhundho jo match kar sake
            for i, pos in enumerate(open_positions):
                if pos["side"] != side and pos["remaining"] > 0:
                    match_size = min(pos["remaining"], size)

                    # Entry aur Exit dono ki fees add karo
                    trades.append({
                        "symbol": symbol,
                        "entry_side": pos["side"],
                        "entry_price": pos["price"],
                        "exit_price": price,
                        "size": match_size,
                        "entry_time": pos["time"],
                        "exit_time": time,
                        "entry_fill_id": pos["fill_id"],
                        "exit_fill_id": fill_id,
                        "fee": pos["fee"] + fee,          # Dono fills ki fees
                        "funding": pos["funding"] + funding,
                    })

                    pos["remaining"] -= match_size
                    size -= match_size

                    if pos["remaining"] <= 0:
                        open_positions.pop(i)
                    break

            # Agar kuch bacha hai, to naya position open karo
            if size > 0:
                open_positions.append({
                    "side": side,
                    "price": price,
                    "remaining": size,
                    "time": time,
                    "fill_id": fill_id,
                    "fee": fee,
                    "funding": funding,
                })

    return trades


def add_grouped_trade(trade):
    """Grouped trade Supabase mein daalta hai.
    PnL = gross PnL (Delta ke Realised PnL se match).
    Fee = entry + exit dono ki fees."""
    from delta_client import get_contract_value

    trade_id = f"{trade['entry_fill_id']}_{trade['exit_fill_id']}"

    symbol = trade["symbol"]
    entry_price = float(trade["entry_price"] or 0)
    exit_price = float(trade["exit_price"] or 0)
    size = float(trade["size"] or 0)
    side = trade["entry_side"]
    fee = float(trade["fee"] or 0)
    funding = float(trade["funding"] or 0)

    lot_size = get_contract_value(symbol)

    # Gross PnL (fees se pehle — Delta ke saath match)
    if side == "buy":
        gross_pnl = (exit_price - entry_price) * size * lot_size
    else:
        gross_pnl = (entry_price - exit_price) * size * lot_size

    data = {
        "delta_order_id": trade_id,
        "symbol": symbol,
        "side": side,
        "size": size,
        "entry_price": entry_price,
        "exit_price": exit_price,
        "pnl": round(gross_pnl, 6),
        "fee": round(fee, 8),
        "funding": round(funding, 8),
        "trade_time": trade["entry_time"],
        "note": ""
    }

    try:
        supabase.table(TABLE).upsert(data, on_conflict="delta_order_id").execute()
        return True
    except Exception as e:
        print(f"Supabase error: {e}")
        return False


def get_trades():
    response = supabase.table(TABLE).select("*").order("trade_time", desc=True).execute()
    return response.data


def update_note(trade_id, note):
    supabase.table(TABLE).update({"note": note}).eq("id", trade_id).execute()


def update_exit_price(trade_id, exit_price):
    """Exit price update karta hai aur PnL automatically calculate karta hai.
    Yeh manual override ke liye hai (agar auto-calculate galat lage)."""
    from delta_client import get_contract_value

    result = supabase.table(TABLE).select("*").eq("id", trade_id).execute()
    if not result.data:
        return False

    trade = result.data[0]
    entry = float(trade.get("entry_price") or 0)
    size = float(trade.get("size") or 0)
    side = trade.get("side")
    symbol = trade.get("symbol")

    lot_size = get_contract_value(symbol)

    if side == "buy":
        pnl = (float(exit_price) - entry) * size * lot_size
    else:
        pnl = (entry - float(exit_price)) * size * lot_size

    supabase.table(TABLE).update({
        "exit_price": float(exit_price),
        "pnl": round(pnl, 6),
    }).eq("id", trade_id).execute()
    return True


def delete_all_trades():
    supabase.table(TABLE).delete().neq("id", 0).execute()
