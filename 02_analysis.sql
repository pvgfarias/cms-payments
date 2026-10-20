-- Q1. Which 10 companies paid physicians the most in 2025?
-- The data shows that the top 10 is about 33.5% of all payments to physicians.
-- It also shows that 8 out of 10 companies are related to medical device makers while 2 are related to drugs.
SELECT gptab.company_id, dim.company, 
  round(sum(gptab.amount) / 1e6, 1) AS usd_millions, 
  ROUND((sum(gptab.amount)/
 (SELECT sum(amount)
    FROM gp 
    WHERE program_year = 2025 
    AND recipient_type = 'Covered Recipient Physician'))*100, 1) as percentage
  FROM gp AS gptab
  JOIN dim_company AS dim
  ON dim.company_id = gptab.company_id
  WHERE program_year = 2025 AND recipient_type = 'Covered Recipient Physician' 
  GROUP BY gptab.company_id, dim.company
  ORDER BY usd_millions DESC
  LIMIT 10 ;


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