# retail-etl-pipeline

> End-to-end ETL pipeline that ingests real e-commerce transaction data, transforms and loads it into a star-schema data warehouse, and delivers actionable business insights through SQL analysis.

---

## Business Context

A UK-based online gift retailer needs to understand what drove their business performance during 2010–2011. The company sells to both wholesale (B2B) and retail (B2C) customers across 38 countries.

This project builds the full data infrastructure to answer those questions — from raw Excel file to a structured data warehouse with 539,392 clean transactions ready for analysis.

---

## Business Questions Answered

| # | Question | Finding |
|---|---|---|
| 1 | Which products generate 80% of revenue? | 21.1% of products (824/3,912) drive 80% of £10.27M revenue |
| 2 | Which markets perform best? | UK dominates at 84.6%; Netherlands and EIRE lead internationally |
| 3 | When do sales peak? | November peak (£1.51M); Thursday highest volume; zero weekends = B2B |
| 4 | Which high-value customers are churning? | 20 customers >£1K at risk; top 3 represent £161K recoverable revenue |
| 5 | Which products have quality issues? | Rotating Silver Angels 98.9% return rate; Chandelier line 55–65% |
| 6 | What is the customer value distribution? | 1,008 lost customers avg £3,760 — highest value segment lost |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        DATA SOURCE                          │
│                                                             │
│   UCI Online Retail Dataset — 541,909 raw transactions      │
│   UK gift retailer · Dec 2010 – Dec 2011 · 38 countries     │
└──────────────────────┬──────────────────────────────────────┘
                       │ Extract
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              TRANSFORMATION (Python + Pandas)               │
│                                                             │
│   Data quality assessment · Stock adjustment removal        │
│   Cancellation flagging · CustomerID normalization          │
│   B2B/B2C segmentation · Surrogate key generation           │
│   Internal code detection · Dimension building              │
└──────────────────────┬──────────────────────────────────────┘
                       │ Load
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              DATA WAREHOUSE (MySQL — Star Schema)           │
│                                                             │
│   fact_sales (539,392 rows)                                 │
│   dim_product · dim_customer · dim_date · dim_geography     │
└──────────────────────┬──────────────────────────────────────┘
                       │ Analyze
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                     BUSINESS ANALYSIS                       │
│                                                             │
│   Pareto · Geographic · Seasonality · Churn · RFM           │
└─────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Python 3.11 |
| Data manipulation | Pandas, SQLAlchemy |
| Database | MySQL 8.0 |
| Notebooks | Jupyter |
| Version control | Git + GitHub |

---

## Data Source

**UCI Online Retail Dataset**
- Origin: UCI Machine Learning Repository (CC BY 4.0)
- Raw size: 541,909 transactions
- Clean size: 539,392 rows after ETL
- Coverage: Dec 2010 – Dec 2011, 38 countries, 4,371 unique customers

**Data quality issues handled:**

| Issue | Count | Action |
|---|---|---|
| Null CustomerID | 135,080 (24.9%) | Assigned to UNKNOWN placeholder |
| Null Description | 1,454 (0.3%) | Filled with 'No description' |
| Stock adjustments | 1,336 (0.2%) | Excluded (zero price, no customer) |
| Cancelled invoices | 9,288 (1.7%) | Flagged as is_return = 1 |
| Zero/negative unit price | 1,181 (0.2%) | Excluded from regular sales |
| Internal stock codes | 12 codes | Flagged with is_internal = 1 |

---

## Data Warehouse Schema

```
fact_sales (539,392 rows)
├── sale_id          PK
├── date_key         FK → dim_date
├── product_key      FK → dim_product
├── customer_key     FK → dim_customer
├── geography_key    FK → dim_geography
├── invoice_no
├── quantity
├── unit_price
├── total_revenue
├── is_return        0 = sale, 1 = return
└── source           'uci'

dim_product (3,938 rows)
├── product_key      PK
├── stock_code
├── description
├── category
├── unit_price_ref
├── is_internal      0 = real product, 1 = fee/adjustment
└── source

dim_customer (4,372 rows)
├── customer_key     PK
├── customer_id
├── segment          'B2B' | 'B2C' | 'unknown'
├── country
└── first_order_date

dim_date (374 rows)
├── date_key         PK (YYYYMMDD)
├── full_date
├── year, quarter, month, week
├── day_of_week, day_name
└── is_weekend

dim_geography (38 rows)
├── geography_key    PK
└── country
```

---

## Key Findings

### 1. Pareto Analysis
21.1% of products (824 out of 3,912) generate 80% of total revenue (£8.2M).
The top product — REGENCY CAKESTAND 3 TIER — alone generates £174K (1.7% of total).

### 2. Geographic Concentration
The UK accounts for 84.6% of revenue (£9.03M). All 37 international markets
combined represent only 15.4%. Netherlands (£285K) and EIRE (£283K) are the
strongest international markets despite having only 9 and 4 customers respectively.

### 3. Seasonality
November 2011 is the peak month at £1.51M (2,769 orders). Revenue grows
consistently from September through November — a clear Christmas gift cycle.
Thursday is the highest volume day; zero weekend transactions confirms
predominantly B2B wholesale behavior.

### 4. Churn Risk
20 high-value customers (>£1K revenue) have not ordered in 60+ days.
Customer 12346 (B2B, £77K revenue) has been silent for 325 days.
The top 3 at-risk customers represent £161K in potentially recoverable revenue.

### 5. Return Rate Issues
The Rotating Silver Angels T-Light Holder has a 98.94% return rate on 9,476 units —
a clear product defect. The Chandelier T-Light product line (3 SKUs) shows
systematic 55–65% return rates suggesting a range-wide quality issue.

### 6. RFM Customer Segmentation

| Segment | Customers | Avg Revenue | Priority |
|---|---|---|---|
| Lost | 1,008 | £3,760 | Win-back campaign |
| Champions | 918 | £253 | Retain and reward |
| Loyal | 883 | £460 | Upsell |
| Potential | 864 | £3,736 | Convert to loyal |
| At Risk | 449 | £393 | Re-engagement |
| New Customer | 216 | £1,502 | Onboarding |

Lost customers have the highest average revenue — the business is losing its
most valuable customers. A targeted win-back campaign could recover significant revenue.

---

## Project Structure

```
retail-etl-pipeline/
│
├── data/
│   └── raw/                        # Source files (gitignored)
│
├── notebooks/
│   ├── 01_exploration.ipynb        # Data quality assessment
│   ├── 02_transform.ipynb          # ETL pipeline + warehouse load
│   └── 03_analysis.ipynb           # Business analysis + findings
│
├── warehouse/
│   ├── schema_oltp.sql             # Source database DDL
│   └── schema_dwh.sql              # Star schema DDL + KPI views
│
├── scripts/
│   └── etl_pipeline.py             # ETL pipeline script
│
├── .env.example                    # Environment variables template
├── requirements.txt                # Python dependencies
└── README.md
```

---

## Getting Started

### Prerequisites
- Python 3.11+
- MySQL 8.0
- Git

### 1. Clone the repo
```bash
git clone https://github.com/<your-username>/retail-etl-pipeline.git
cd retail-etl-pipeline
```

### 2. Create and activate virtual environment
```bash
python -m venv venv
venv\Scripts\activate        # Windows
source venv/bin/activate     # Mac/Linux
pip install -r requirements.txt
```

### 3. Set up environment variables
```bash
cp .env.example .env
# Edit .env with your MySQL credentials
```

### 4. Create the database schemas
Run `warehouse/schema_dwh.sql` in MySQL Workbench or any MySQL client.

### 5. Download the dataset
Download the UCI Online Retail dataset from:
https://archive.ics.uci.edu/dataset/352/online+retail

Place `Online Retail.xlsx` in the `data/raw/` folder.

### 6. Run the notebooks in order
```
notebooks/01_exploration.ipynb   # Understand the data
notebooks/02_transform.ipynb     # Clean, transform, and load
notebooks/03_analysis.ipynb      # Business analysis
```

---

## Status

- [x] Data quality assessment (notebook 01)
- [x] ETL pipeline — extraction, transformation, loading (notebook 02)
- [x] Star schema data warehouse in MySQL
- [x] Business analysis — 6 findings (notebook 03)
- [x] Pareto analysis
- [x] Geographic revenue breakdown
- [x] Seasonality analysis
- [x] Customer churn detection
- [x] Return rate analysis
- [x] RFM customer segmentation
- [x] Automated pipeline orchestration
- [ ] Visualization dashboard 

---

## Author
**Alejandro Robles Lizarraga**

Built as a portfolio project demonstrating end-to-end data engineering skills:
ETL pipeline design, star schema data warehouse modeling, Python automation,
MySQL optimization, and business intelligence analysis on real transactional data.
