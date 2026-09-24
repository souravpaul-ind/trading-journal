import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_KEY")
supabase: Client = create_client(url, key)

# Table ka naam
TABLE = "trades"

# Root folder mein .env hai, isliye path do
load_dotenv(dotenv_path="../.env")

def init_db():
    """Supabase mein table pehle se banana padega (Dashboard ke Table Editor se).
    Yeh function sirf check karta hai ki connection chal raha hai."""
    try:
        supabase.table(TABLE).select("id").limit(1).execute()
        print("Supabase connected ✓")
    except Exception as e:
        print(f"Supabase connection error: {e}")

def add_trade(order):
    """Delta se aaya order Supabase mein daalta hai.
    upsert use karo taaki duplicate order ID pe error na aaye."""
    data = {
        "delta_order_id": str(order.get("id")),
        "symbol": order.get("product_symbol"),
        "side": order.get("side"),
        "size": order.get("size"),
        "entry_price": order.get("avg_fill_price") or order.get("limit_price"),
        "exit_price": order.get("avg_fill_price") or order.get("limit_price"),
        "pnl": order.get("realised_pnl", 0),
        "fee": order.get("fee", 0),
        "funding": order.get("funding", 0),
        "trade_time": order.get("created_at"),
        "note": ""
    }
    
    # upsert: agar delta_order_id pehle se hai to skip kar do
    # (on_conflict wale column pe UNIQUE constraint hona chahiye)
    supabase.table(TABLE).upsert(
        data, 
        on_conflict="delta_order_id"
    ).execute()

def get_trades():
    """Saare trades nikalta hai, naye sabse pehle"""
    response = supabase.table(TABLE).select("*").order("trade_time", desc=True).execute()
    return response.data

def update_note(trade_id, note):
    """Kisi trade ka note update karta hai (id se match karke)"""
    supabase.table(TABLE).update({"note": note}).eq("id", trade_id).execute()

def update_funding(trade_id, funding):
    """Funding manually update karne ke liye"""
    supabase.table(TABLE).update({"funding": funding}).eq("id", trade_id).execute()