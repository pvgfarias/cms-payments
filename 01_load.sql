-- 01_load.sql  —  CMS Open Payments, General Payments, PY2024 + PY2025
-- Run:  duckdb openpayments.duckdb < 01_load.sql
-- /data has the PY2024 AND PY2025 files that have around 8GB each 

SET memory_limit = '8GB';        -- adjust to your machine
SET preserve_insertion_order = false;

-- 1: Creating the first table with all the initial data. 
-- Considers everything as text to avoid that some bad value like $1,300 or N/A won't break the load.
CREATE OR REPLACE TABLE raw_general AS
SELECT *
FROM read_csv(
    'data/OP_DTL_GNRL_PGYR202[45]_*.csv',
    header          = true,       -- reads the columns in the 1st line of the csv file
    all_varchar     = true,       -- considers all as text to avoid potential errors
    union_by_name   = true,       -- matches columns by name in case they are in different positions across years
    filename        = true,       -- adds a column to show which file each row is from
    ignore_errors   = true        -- if the row is unreadable, skips. compare to total rows and columns later on.
);

-- 2. Creates the gp table using easier to read column names to facilitate analysis.
-- It also creates the appropriate types for each column.
-- Because of TRY_CAST, the bad values become null in case of an error
CREATE OR REPLACE TABLE gp AS
SELECT
    TRY_CAST(Program_Year AS INTEGER)                                   AS program_year,    -- if an invalid number in program year it'll become null
    Record_ID                                                           AS record_id,
    Covered_Recipient_Type                                              AS recipient_type,
    Covered_Recipient_Profile_ID                                        AS recipient_id,
    Covered_Recipient_NPI                                               AS npi,
    trim(Covered_Recipient_First_Name || ' ' || Covered_Recipient_Last_Name) AS recipient_name,     -- joining first and last name to get one readable name
    Recipient_State                                                     AS state,
    Covered_Recipient_Specialty_1                                       AS specialty_raw,   -- specialties are delimited by | in a pipe-delimited taxonomy here we get the full text
    NULLIF(split_part(Covered_Recipient_Specialty_1, '|', 2), '')       AS specialty,       -- here we check for the second value in the full specialties text
    NULLIF(split_part(Covered_Recipient_Specialty_1, '|', 3), '')       AS subspecialty,    -- here for the third value in the full specialties text
    Applicable_Manufacturer_or_Applicable_GPO_Making_Payment_ID         AS company_id,      -- if grouping, use company_id rather than company name since they can vary slightly
    Applicable_Manufacturer_or_Applicable_GPO_Making_Payment_Name       AS company,
    TRY_CAST(Total_Amount_of_Payment_USDollars AS DECIMAL(18,2))        AS amount,          -- if an invalid value in total amount of payment then it'll become null
    -- changing from text into a date format, if it fails try_Strptime will make it null, 
    -- it tries either of the two formats and keeps whichever worked via coalesce 
    COALESCE(TRY_STRPTIME(Date_of_Payment, '%m/%d/%Y'),
             TRY_STRPTIME(Date_of_Payment, '%Y-%m-%d'))::DATE           AS payment_date,    
    Nature_of_Payment_or_Transfer_of_Value                              AS nature,
    Form_of_Payment_or_Transfer_of_Value                                AS form,
    Name_of_Drug_or_Biological_or_Device_or_Medical_Supply_1            AS product
FROM raw_general;

-- 3. Since company names can differ slightly through files, here we check for each company what's the most common used name and adhere to it
-- dim refers to the dimension table that we will join to the main table to serve as lookup
CREATE OR REPLACE TABLE dim_company AS
SELECT company_id, arg_max(company, n) AS company                       -- here we select the one with most occurrences
FROM (SELECT company_id, company, count(*) AS n FROM gp GROUP BY ALL)   -- subquery that checks how many times a specific spelling for a company name appears
GROUP BY company_id;

-- 4. Physician-year rollup: a summary of the payments involving physicians per year. 
-- We summarize everything into one row per physician to facilitate analysis later on about things like what specialties were the top 1% doctors associated with. 
CREATE OR REPLACE TABLE physician_year AS
SELECT
    program_year, recipient_id,                     -- the year/id that we will also use to group the rows
    any_value(recipient_name) AS recipient_name,    -- physician's name (any_value is needed here and in the following lines because of the GROUP BY, we only need any value since they repeat)
    any_value(specialty)      AS specialty,         -- physician's specialty
    any_value(state)          AS state,             -- physician's state
    sum(amount)               AS total_usd,         -- total amount of USD they got paid
    count(*)                  AS n_payments,        -- number of payments they received
    count(DISTINCT company_id) AS n_companies       -- number of companies that made those payments
FROM gp
WHERE recipient_type = 'Covered Recipient Physician'    -- data contains information about other roles too but we only want physicians
GROUP BY program_year, recipient_id; 

DROP TABLE raw_general;   -- reclaim space once gp looks right

-- 5. Sanity checks. Compare against CMS's published totals:
--    PY2025 general payments: ~$3.92B (https://www.cms.gov/priorities/key-initiatives/open-payments/data)
--    PY2024 general payments: ~$3.33B (https://www.cms.gov/files/document/open-payments-fy-2025-report-congress.pdf)
SELECT program_year, recipient_type,
       count(*) AS records, round(sum(amount)/1e9, 3) AS usd_bn,    -- here we count the total number of records and also the total payments amount converted to billions
       count(*) FILTER (WHERE amount IS NULL) AS bad_amounts,       -- count how many amounts weren't properly loaded
       count(*) FILTER (WHERE payment_date IS NULL) AS bad_dates    -- count how many dates failed being loaded
FROM gp GROUP BY ALL ORDER BY ALL;                                  -- duckdb shortcut, same as writing program_year, recipient_type (columns that weren't aggregated)