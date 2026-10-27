# Who gets paid by the medical industry?

An analysis of 2025 CMS Open Payments data: $2.6 billion in general payments
from drug and device companies to U.S. physicians, using SQL (DuckDB).

## Key findings

1. **Payments are highly concentrated.** The top 1% of physicians (6,668 doctors,
   each receiving at least $66,326) received **64.8%** of all payments in 2025.
2. **Orthopaedic surgeons receive the most per doctor.** They received an average
   of **$23,569** each, nearly 5x the average internal medicine physician.
   Internal medicine and orthopaedic surgery together received 51% of all payments.
3. **Device makers dominate the top payers.** The top 10 companies paid **33.5%**
   of the total, and 8 of the 10 are medical device makers, not drug companies.

## Data

- Source: [CMS Open Payments](https://openpaymentsdata.cms.gov/), General Payments,
  program years 2024 and 2025 (about 16 million records per year).
- Scope: general payments only (not research or ownership); findings cover physicians only.
- Validation: loaded totals matched CMS's published 2025 figure within 0.1%.
  2024 came out about 3% higher, consistent with corrections CMS adds after the first release.

## How to run

1. Download the General Payments CSVs for 2024 and 2025 into `data/`.
2. Run `duckdb openpayments.duckdb < 01_load.sql` to load and clean the data.
3. Run any query file, for example `.read 02_analysis.sql` inside DuckDB.

## Tools

DuckDB (SQL), Git. A Tableau dashboard is coming next.

## Next steps

- What types of payments (royalties, consulting, meals) drive the concentration?
- How did payments change between 2024 and 2025?
