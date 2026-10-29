-- 03_exports.sql: export the three findings to CSV for Tableau.
-- Run inside DuckDB after opening openpayments.duckdb:  .read 03_exports.sql
-- The CSVs are written to the folder DuckDB was started from (they're ignored by git).

-- Q1. Top 10 companies paying physicians in 2025
COPY (
  WITH company_totals AS (
    SELECT g.company_id, d.company, SUM(g.amount) AS company_total
    FROM gp AS g
    JOIN dim_company AS d
      ON d.company_id = g.company_id
    WHERE program_year = 2025 AND recipient_type = 'Covered Recipient Physician'
    GROUP BY g.company_id, d.company
  ),
  grand_total AS (
    SELECT SUM(company_total) AS total FROM company_totals
  )
  SELECT company,
    ROUND(company_total/1e6, 1) AS usd_millions,
    ROUND((company_total/total)*100, 1) AS pct_of_total
  FROM company_totals
  CROSS JOIN grand_total
  ORDER BY company_total DESC
  LIMIT 10
) TO 'q1_top_companies.csv' (HEADER);

-- Q2. Top 15 specialties in 2025, with average per physician
COPY (
  WITH specialty_totals AS (
    SELECT COALESCE(specialty, 'Unknown') AS specialty,
      SUM(total_usd) AS specialty_total,
      COUNT(recipient_id) AS physicians
    FROM physician_year
    WHERE program_year = 2025
    GROUP BY COALESCE(specialty, 'Unknown')
  ),
  grand_total AS (
    SELECT SUM(specialty_total) AS total FROM specialty_totals
  )
  SELECT specialty,
    ROUND(specialty_total/1e6, 1) AS usd_millions,
    physicians,
    ROUND(specialty_total/physicians, 0) AS usd_per_physician,
    ROUND((specialty_total/total)*100, 1) AS pct_of_total
  FROM specialty_totals
  CROSS JOIN grand_total
  ORDER BY specialty_total DESC
  LIMIT 15
) TO 'q2_specialties.csv' (HEADER);

-- Q3. Top 1% of physicians vs the other 99%, as two rows so it can be charted
COPY (
  WITH cutoff AS (
    SELECT quantile_cont(total_usd, 0.99) AS cut
    FROM physician_year
    WHERE program_year = 2025
  ),
  grand_total AS (
    SELECT SUM(total_usd) AS total
    FROM physician_year
    WHERE program_year = 2025
  ),
  top_1_pct AS (
    SELECT SUM(total_usd) AS physician_total
    FROM physician_year
    CROSS JOIN cutoff
    WHERE total_usd >= cut AND program_year = 2025
  ),
  share AS (
    SELECT t.physician_total / gt.total * 100 AS pct
    FROM top_1_pct AS t
    CROSS JOIN grand_total AS gt
  )
  SELECT 'Top 1%' AS doctors, ROUND(pct, 1) AS pct_of_total FROM share
  UNION ALL
  SELECT 'Other 99%', ROUND(100 - pct, 1) FROM share
) TO 'q3_concentration.csv' (HEADER);