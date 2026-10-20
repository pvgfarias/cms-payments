-- 02_analysis.sql  —  run in the DuckDB CLI after 01_load.sql
-- Scope: physicians only (NPPs and teaching hospitals behave very differently).

------------------------------------------------------------------
-- Q1. Which specialties get the most money? Share + YoY change.
------------------------------------------------------------------
WITH s AS (
    SELECT program_year, coalesce(specialty, '(unknown)') AS specialty,
           sum(total_usd) AS usd, count(*) AS physicians,
           median(total_usd) AS median_per_physician
    FROM physician_year GROUP BY ALL
)
SELECT *,
       round(100 * usd / sum(usd) OVER (PARTITION BY program_year), 2) AS pct_of_year,
       rank() OVER (PARTITION BY program_year ORDER BY usd DESC)        AS rnk,
       round(100 * (usd / lag(usd) OVER (PARTITION BY specialty ORDER BY program_year) - 1), 1) AS yoy_pct
FROM s
QUALIFY rnk <= 15
ORDER BY program_year DESC, rnk;

------------------------------------------------------------------
-- Q2. Which companies pay the most? Share, YoY, and cumulative share.
------------------------------------------------------------------
WITH c AS (
    SELECT g.program_year, d.company, sum(g.amount) AS usd,
           count(DISTINCT g.recipient_id) AS physicians_paid
    FROM gp g JOIN dim_company d USING (company_id)
    WHERE g.recipient_type = 'Covered Recipient Physician'
    GROUP BY ALL
)
SELECT *,
       round(100 * usd / sum(usd) OVER (PARTITION BY program_year), 2) AS pct_of_year,
       round(100 * sum(usd) OVER (PARTITION BY program_year ORDER BY usd DESC)
                 / sum(usd) OVER (PARTITION BY program_year), 1)       AS cum_pct,
       round(100 * (usd / lag(usd) OVER (PARTITION BY company ORDER BY program_year) - 1), 1) AS yoy_pct
FROM c
QUALIFY rank() OVER (PARTITION BY program_year ORDER BY usd DESC) <= 20
ORDER BY program_year DESC, usd DESC;

------------------------------------------------------------------
-- Q3. How concentrated are payments among top recipients?
--     Top 0.1% / 1% / 10% share, median vs mean, Gini.
------------------------------------------------------------------
WITH ranked AS (
    SELECT program_year, total_usd,
           row_number() OVER (PARTITION BY program_year ORDER BY total_usd DESC) AS r_desc,
           row_number() OVER (PARTITION BY program_year ORDER BY total_usd ASC)  AS r_asc,
           count(*)     OVER (PARTITION BY program_year)                        AS n
    FROM physician_year WHERE total_usd > 0
)
SELECT program_year,
       any_value(n)                                    AS physicians,
       round(sum(total_usd)/1e9, 3)                    AS usd_bn,
       round(median(total_usd), 0)                     AS median_usd,
       round(avg(total_usd), 0)                        AS mean_usd,
       round(100 * sum(total_usd) FILTER (WHERE r_desc <= n * 0.001) / sum(total_usd), 1) AS top_0_1_pct_share,
       round(100 * sum(total_usd) FILTER (WHERE r_desc <= n * 0.01)  / sum(total_usd), 1) AS top_1_pct_share,
       round(100 * sum(total_usd) FILTER (WHERE r_desc <= n * 0.10)  / sum(total_usd), 1) AS top_10_pct_share,
       -- Gini on sorted-ascending values: sum((2i - n - 1) * x) / (n * sum(x))
       round(sum((2 * r_asc - n - 1) * total_usd) / (any_value(n) * sum(total_usd)), 3)  AS gini
FROM ranked
GROUP BY program_year ORDER BY program_year;

------------------------------------------------------------------
-- Q4. WHY is it concentrated? Dollar mix vs record mix by payment nature.
--     (Expect: food & beverage dominates record counts; royalties,
--      consulting and speaker fees dominate dollars.)
------------------------------------------------------------------
SELECT program_year, nature,
       count(*) AS records,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY program_year), 1) AS pct_records,
       round(sum(amount)/1e6, 1) AS usd_mm,
       round(100 * sum(amount) / sum(sum(amount)) OVER (PARTITION BY program_year), 1) AS pct_usd
FROM gp
WHERE recipient_type = 'Covered Recipient Physician'
GROUP BY program_year, nature
ORDER BY program_year DESC, usd_mm DESC;

------------------------------------------------------------------
-- Q5. Year-over-year shift at the top: how sticky is the top 1%?
------------------------------------------------------------------
WITH top1 AS (
    SELECT program_year, recipient_id
    FROM physician_year
    QUALIFY percent_rank() OVER (PARTITION BY program_year ORDER BY total_usd DESC) < 0.01
)
SELECT
    count(*) FILTER (WHERE a.recipient_id IS NOT NULL AND b.recipient_id IS NOT NULL) AS in_both,
    count(*) FILTER (WHERE b.recipient_id IS NULL)  AS dropped_out_2025,
    count(*) FILTER (WHERE a.recipient_id IS NULL)  AS new_in_2025,
    round(100.0 * count(*) FILTER (WHERE a.recipient_id IS NOT NULL AND b.recipient_id IS NOT NULL)
          / count(a.recipient_id), 1) AS pct_2024_top1_retained
FROM (SELECT recipient_id FROM top1 WHERE program_year = 2024) a
FULL OUTER JOIN (SELECT recipient_id FROM top1 WHERE program_year = 2025) b USING (recipient_id);

------------------------------------------------------------------
-- Q6. Company concentration (HHI) overall and within each top specialty.
--     HHI > 2500 = highly concentrated (DOJ convention), on 0-10000 scale.
------------------------------------------------------------------
WITH shares AS (
    SELECT program_year, coalesce(specialty, '(unknown)') AS specialty, company_id,
           sum(amount) / sum(sum(amount)) OVER (PARTITION BY program_year, coalesce(specialty, '(unknown)')) AS sh
    FROM gp WHERE recipient_type = 'Covered Recipient Physician'
    GROUP BY program_year, coalesce(specialty, '(unknown)'), company_id
)
SELECT program_year, specialty, round(10000 * sum(sh * sh)) AS hhi, count(*) AS companies
FROM shares GROUP BY ALL
HAVING count(*) >= 20
ORDER BY program_year DESC, hhi DESC
LIMIT 30;

------------------------------------------------------------------
-- Tableau exports. Tableau doesn't connect to DuckDB cleanly (esp. Tableau
-- Public), so hand it small, pre-aggregated files.
------------------------------------------------------------------
COPY (SELECT * FROM physician_year)
  TO 'tableau/physician_year.csv' (HEADER);

COPY (SELECT g.program_year, coalesce(g.specialty,'(unknown)') AS specialty, d.company,
             g.nature, g.state, date_trunc('month', g.payment_date) AS month,
             count(*) AS records, sum(g.amount) AS usd
      FROM gp g JOIN dim_company d USING (company_id)
      WHERE g.recipient_type = 'Covered Recipient Physician'
      GROUP BY ALL)
  TO 'tableau/payments_cube.csv' (HEADER);