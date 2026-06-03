# Load the libreries and the data
import pandas as pd
import numpy as np
import os
import time
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from pathlib import Path

load_dotenv()

project_root = Path(__file__).resolve().parent.parent
raw_data_path = project_root / "data" / "raw" / "Online_Retail.xlsx"

print("[INFO] Loading source data...")
raw_online_retail = pd.read_excel(raw_data_path)
print("[Success] Data loaded successfully.")

print("\n[INFO] Applying data transformations...")

# Lowercase columns
raw_online_retail.columns = raw_online_retail.columns.str.lower()

# Exclude rows with zero price, no description, no customer
mask_adjustment = (
    (raw_online_retail['quantity'] < 0) &
    (raw_online_retail['unitprice'] == 0) &
    (~raw_online_retail['invoiceno'].astype(str).str.startswith('C'))
)
online_retail = raw_online_retail[~mask_adjustment].copy()

# Flag cancelled invoices as returns
online_retail['is_return'] = online_retail['invoiceno'].astype(
    str).str.startswith('C').astype(int)

# Cast customerID float to string and fill nulls
online_retail['customerid'] = (online_retail['customerid'].fillna(0).astype(int).astype(str)
                               .replace('0', 'UNKNOWN'))

# Fill null descriptions
online_retail['description'] = online_retail['description'].fillna(
    'No description')

# Keep zero prices only on returns, exclude on regular sales
mask_bad_price = (online_retail['unitprice'] <= 0) & (
    online_retail['is_return'] == 0)
online_retail = online_retail[~mask_bad_price].copy()

online_retail['total_revenue'] = (
    online_retail['quantity'] * online_retail['unitprice']).round(2)

# create the same tables as the server (MySQL local host in this case)
# generate one row per unique date in the dataset
dates = pd.DataFrame({'full_date': pd.date_range(
    start=online_retail['invoicedate'].min().date(),
    end=online_retail['invoicedate'].max().date(),
    freq='D'
)})

dates['date_key'] = dates['full_date'].dt.strftime('%Y%m%d').astype(int)
dates['year'] = dates['full_date'].dt.year
dates['quarter'] = dates['full_date'].dt.quarter
dates['month'] = dates['full_date'].dt.month
dates['month_name'] = dates['full_date'].dt.strftime('%B')
dates['week'] = dates['full_date'].dt.isocalendar().week.astype(int)
dates['day_of_month'] = dates['full_date'].dt.day
dates['day_of_week'] = dates['full_date'].dt.dayofweek + 1  # 1=Mon, 7=Sun
dates['day_name'] = dates['full_date'].dt.strftime('%A')
dates['is_weekend'] = (dates['day_of_week'] >= 6).astype(int)
dates['is_holiday'] = 0

dim_geography = (
    online_retail[['country']].drop_duplicates().reset_index(drop=True)
)
dim_geography['geography_key'] = dim_geography.index + 1
dim_geography['region'] = None
dim_geography['iso_code'] = None

# Obtain the iso code


dim_product = (
    online_retail[['stockcode', 'description', 'unitprice']
                  ].sort_values('unitprice', ascending=False)
    .drop_duplicates(subset='stockcode', keep='first').reset_index(drop=True)
)
dim_product['product_key'] = dim_product.index + 1
dim_product['category'] = None
dim_product['source'] = 'uci'
dim_product = dim_product.rename(columns={'unitprice': 'unit_price_ref'})

# Calculate average order quantity per customer
avg_quantity = (
    online_retail[online_retail['is_return'] == 0]
    .groupby('customerid')['quantity'].mean().reset_index()
    .rename(columns={'quantity': 'avg_quantity'})
)

dim_customer = (
    online_retail[['customerid', 'country']]
    .drop_duplicates(subset='customerid', keep='first')
    .reset_index(drop=True)
)
dim_customer['customer_key'] = dim_customer.index + 1
dim_customer['first_order_date'] = (
    online_retail.groupby('customerid')['invoicedate'].min()
    .dt.date.reset_index(drop=True)
)

# Merge average quantity and assign segment
dim_customer = dim_customer.merge(avg_quantity, on='customerid', how='left')
dim_customer['segment'] = dim_customer['avg_quantity'].apply(
    lambda x: "B2B" if x > 100 else "B2C")

dim_customer = dim_customer.drop(columns='avg_quantity')

# Fix UNKNOWN customer row
mask_unknown = dim_customer['customerid'] == 'UNKNOWN'
dim_customer.loc[mask_unknown, 'first_order_date'] = None
dim_customer.loc[mask_unknown, 'country'] = None
dim_customer.loc[mask_unknown, 'segment'] = 'unknown'

# Internal codes START with a letter
dim_product['is_internal'] = dim_product['stockcode'].str.match(
    r'^[^0-9]', na=False)

dim_product.loc[
    dim_product['stockcode'].str.startswith(('DCGS', 'gift'), na=False),
    'is_internal'
] = False

# Build fact_sales by joining online_retail with dimensions keys
fact_sales = online_retail.copy()
fact_sales['date_key'] = fact_sales['invoicedate'].dt.strftime(
    '%Y%m%d').astype(int)

fact_sales = fact_sales.merge(
    dim_product[['stockcode', 'product_key']],
    on='stockcode', how='left'
)

fact_sales = fact_sales.merge(
    dim_customer[['customerid', 'customer_key']],
    on='customerid', how='left'
)

fact_sales = fact_sales.merge(
    dim_geography[['country', 'geography_key']],
    on='country', how='left'
)

fact_sales = fact_sales[[
    'date_key', 'product_key', 'customer_key', 'geography_key',
    'invoiceno', 'quantity', 'unitprice', 'total_revenue', 'is_return'
]].copy()

fact_sales['source'] = 'uci'

# Rename columns to match MySQL schema exactly
dim_product = dim_product.rename(columns={'stockcode': 'stock_code'})

dim_customer = dim_customer.rename(columns={
    'customerid': 'customer_id',
    'first_order_date': 'first_seen_date'
})

fact_sales = fact_sales.rename(columns={
    'invoiceno': 'invoice_no',
    'unitprice': 'unit_price'
})

print('[SUCCESS] Data transformations completed.')

print('\n[INFO] Connecting to MySQL...')
# Database connection
user = os.getenv("MYSQL_USER")
password = os.getenv("MYSQL_PASSWORD")
host = os.getenv("DWH_HOST")
port = os.getenv("DWH_PORT")
db = os.getenv("DWH_DB")

engine = create_engine(f"mysql+pymysql://{user}:{password}@{host}:{port}/{db}")

with engine.connect() as conn:
    result = conn.execute(text(
        "SELECT 'Connection OK' AS status, DATABASE() AS current_db, VERSION() AS mysql_version"))
    row = result.fetchone()
    print(f"Status: {row[0]}")
    print(f"Database: {row[1]}")
    print(f"MySQL version: {row[2]}")

print('[SUCCESS] Database connection established.')
print('\n[INFO] Uploading data to MySQL...')
tables = {
    'dim_date': dates,
    'dim_geography': dim_geography,
    'dim_product': dim_product,
    'dim_customer': dim_customer,
    'fact_sales': fact_sales
}

for table_name, df_table in tables.items():
    start = time.time()
    df_table.to_sql(
        name=table_name, con=engine,
        if_exists='append', index=False
    )
    elapsed = round(time.time() - start, 2)
    print(f"{table_name}: {len(df_table):,} rows loaded in {elapsed}s")

print()
print('-' * 42)
print('[SUCCESS] All tables loaded successfully.')
