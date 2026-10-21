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
-- Is that because each doctor receive a lot on average or because the specialty has many doctors
SELECT COALESCE(specialty, 'Unknown') as specialty, 
  round(SUM(total_usd) / 1e6, 1) AS usd_millions, 
  COUNT(recipient_id) as physicians, 
  ROUND(SUM(total_usd)/COUNT(recipient_id), 0) as usd_per_physician, 
  round(SUM(total_usd)/(SELECT SUM(total_usd) FROM physician_year WHERE program_year = 2025) *100, 1) as percentage 
  FROM physician_year 
  WHERE program_year = 2025 
  GROUP BY COALESCE(specialty, 'Unknown')
  ORDER BY usd_millions DESC
  LIMIT 15;