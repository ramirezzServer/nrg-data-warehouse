import os
import pandas as pd
import mysql.connector


# =========================================================
# CONFIGURATION
# =========================================================

DB_CONFIG = {
    "host": "localhost",
    "port": 3306,
    "user": "root",
    "password": "",
    "database": "nrg_ecom"
}

DATA_DIR = "S1_ECOM_DB"


# =========================================================
# DATABASE CONNECTION
# =========================================================

conn = mysql.connector.connect(**DB_CONFIG)
cursor = conn.cursor()

print("Connected to MySQL")


# =========================================================
# HELPER
# =========================================================
def load_csv(filename, table, columns, transform=None):
    """
    Membaca CSV kemudian memasukkan data ke tabel MySQL.
    Nilai kosong/NaN akan dikonversi menjadi SQL NULL.
    """

    path = os.path.join(DATA_DIR, filename)

    if not os.path.exists(path):
        print(f"[SKIP] File tidak ditemukan: {path}")
        return

    print(f"\nLoading {filename} -> {table}")

    # Baca CSV
    df = pd.read_csv(path)

    # Transformasi tambahan jika diperlukan
    if transform:
        df = transform(df)

    # Pastikan hanya kolom yang dibutuhkan
    df = df[columns]

    # NaN / NaT -> None
    df = df.astype(object).where(pd.notna(df), None)

    placeholders = ", ".join(["%s"] * len(columns))
    column_names = ", ".join(columns)

    sql = f"""
        INSERT INTO {table}
        ({column_names})
        VALUES ({placeholders})
    """

    data = list(df.itertuples(index=False, name=None))

    try:
        cursor.executemany(sql, data)
        conn.commit()

        print(f"[OK] {len(data)} rows inserted into {table}")

    except Exception as e:
        conn.rollback()
        print(f"[ERROR] Gagal load {filename}")
        print(e)
        raise

# =========================================================
# DISABLE FOREIGN KEY CHECK
# =========================================================

cursor.execute("SET FOREIGN_KEY_CHECKS = 0")


# =========================================================
# 1. CATEGORIES
# =========================================================

load_csv(
    "categories.csv",
    "categories",
    [
        "category_id",
        "parent_category_id",
        "category_name"
    ]
)


# =========================================================
# 2. PRODUCTS
# =========================================================

load_csv(
    "products.csv",
    "products",
    [
        "product_id",
        "sku",
        "category_id",
        "product_name",
        "brand",
        "base_price",
        "is_active"
    ]
)


# =========================================================
# 3. CUSTOMERS
# =========================================================

load_csv(
    "customers.csv",
    "customers",
    [
        "customer_id",
        "full_name",
        "email",
        "phone",
        "gender",
        "birth_date",
        "registered_at"
    ]
)


# =========================================================
# 4. CUSTOMER ADDRESSES
# =========================================================

load_csv(
    "customer_addresses.csv",
    "customer_addresses",
    [
        "address_id",
        "customer_id",
        "label",
        "address_line",
        "city",
        "province",
        "postal_code",
        "is_primary"
    ]
)


# =========================================================
# 5. VOUCHERS
# =========================================================

load_csv(
    "vouchers.csv",
    "vouchers",
    [
        "voucher_id",
        "promo_code",
        "discount_type",
        "discount_value",
        "min_purchase",
        "quota",
        "valid_from",
        "valid_to"
    ]
)


# =========================================================
# 6. ORDERS
# =========================================================

load_csv(
    "orders.csv",
    "orders",
    [
        "order_id",
        "customer_id",
        "order_ts",
        "status",
        "voucher_id",
        "payment_method",
        "shipping_fee",
        "shipping_address_id"
    ]
)


# =========================================================
# 7. ORDER ITEMS
# =========================================================

load_csv(
    "order_items.csv",
    "order_items",
    [
        "order_item_id",
        "order_id",
        "line_no",
        "product_id",
        "sku",
        "qty",
        "unit_price",
        "disc_amount"
    ]
)


# =========================================================
# 8. ORDER STATUS HISTORY
# =========================================================

load_csv(
    "order_status_history.csv",
    "order_status_history",
    [
        "history_id",
        "order_id",
        "status",
        "changed_at"
    ]
)


# =========================================================
# 9. PAYMENTS
# =========================================================

load_csv(
    "payments.csv",
    "payments",
    [
        "payment_id",
        "order_id",
        "provider",
        "amount",
        "paid_at",
        "status"
    ]
)


# =========================================================
# 10. SHIPMENTS
# =========================================================

load_csv(
    "shipments.csv",
    "shipments",
    [
        "shipment_id",
        "order_id",
        "courier",
        "tracking_no",
        "shipped_at",
        "delivered_at"
    ]
)


# =========================================================
# 11. ORDER RETURNS
# =========================================================

load_csv(
    "order_returns.csv",
    "order_returns",
    [
        "return_id",
        "order_item_id",
        "qty",
        "reason",
        "refund_amount",
        "status",
        "requested_at"
    ]
)


# =========================================================
# ENABLE FOREIGN KEY CHECK
# =========================================================

cursor.execute("SET FOREIGN_KEY_CHECKS = 1")

conn.commit()

cursor.close()
conn.close()

print("\n===================================")
print("DATA LOADING SELESAI")
print("===================================")