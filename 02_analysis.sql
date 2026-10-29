-- Q1. Which 10 companies paid physicians the most in 2025?
-- The data shows that the top 10 is 33.5% of all payments to physicians.
-- It also shows that 8 of the 10 are medical device makers, 2 are drug companies.
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
LIMIT 10; 

-- Q2. Which medical specialties received the most money from companies in 2025?
-- Is that because each doctor receives a lot on average or because the specialty has many doctors?
-- Orthopaedic surgeons received $23,569 each on average, nearly 5x internal medicine.
-- Internal medicine is the largest total because it has the most doctors (154k), not because each gets a lot.
-- Internal medicine and orthopaedic surgery together received 51% of all payments to physicians.
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
LIMIT 15;


-- Q3. What share of all money paid to physicians in 2025 went to the top 1% of doctors?
-- The top 1% of physicians (6,668 doctors, each receiving $66,326 or more) received 64.8% of all payments in 2025
WITH cutoff AS (
  SELECT quantile_cont(total_usd, 0.99) AS cut
  FROM physician_year 
  WHERE program_year = 2025
), 
grand_total AS (
  SELECT SUM(total_usd) AS total, COUNT(recipient_id) AS all_doctors
  FROM physician_year 
  WHERE program_year = 2025
),
top_1_pct AS (
  SELECT COUNT(recipient_id) AS physicians, SUM(total_usd) AS physician_total
  FROM physician_year 
  CROSS JOIN cutoff 
  WHERE total_usd >= cut AND
  program_year = 2025
)

SELECT ROUND(c.cut, 0) AS cutoff_usd, 
       t.physicians AS physicians_in_top_1, 
       ROUND(t.physician_total/gt.total * 100, 1) AS pct_of_total,
       gt.all_doctors
FROM cutoff AS c
CROSS JOIN grand_total AS gt
CROSS JOIN top_1_pct AS t;