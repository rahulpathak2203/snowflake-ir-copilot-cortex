-- =====================================================================
-- Halvoran Ridge Capital - structured fund data for Cortex Analyst
-- Fund-level and company-level figures match the PDFs (quarterly letters,
-- portfolio summary, company profiles). Quarterly company financials between
-- entry and Sep 2026 are illustrative but consistent with the documents.
-- All amounts in USD millions. Fictional data.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE IR_WH;
USE SCHEMA IR_COPILOT.FUND_DOCS;

-- ---------------------------------------------------------------------
-- 1. Fund performance: one row per quarter (from the 4 investor letters)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FUND_PERFORMANCE (
  fund_name                 STRING,
  period                    STRING,       -- e.g. 2026-Q3
  quarter_end_date          DATE,
  commitments_musd          NUMBER(10,1),
  net_irr_pct               NUMBER(5,1),  -- since inception, incl. subscription facility
  net_irr_ex_facility_pct   NUMBER(5,1),  -- only disclosed for some quarters
  net_tvpi                  NUMBER(5,2),
  dpi                       NUMBER(5,2),
  pct_capital_called        NUMBER(5,1),
  capital_called_musd       NUMBER(10,1),
  nav_musd                  NUMBER(10,1),
  distributions_musd        NUMBER(10,1)  -- distributed to LPs in that quarter
);

INSERT INTO FUND_PERFORMANCE VALUES
 ('Fund IV','2025-Q4','2025-12-31',6500,12.1,NULL,1.21,0.08,58,3770,4560,  0),
 ('Fund IV','2026-Q1','2026-03-31',6500,12.8,NULL,1.26,0.10,63,4095,4980,130),
 ('Fund IV','2026-Q2','2026-06-30',6500,13.4,12.6,1.31,0.18,68,4420,5310,520),
 ('Fund IV','2026-Q3','2026-09-30',6500,14.0,NULL,1.36,0.22,72,4680,5620,260);

-- ---------------------------------------------------------------------
-- 2. Portfolio companies: one row per company (status as of 2026-Q3)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PORTFOLIO_COMPANIES (
  company_name              STRING,
  fund_name                 STRING,
  sector                    STRING,
  region                    STRING,
  investment_date           DATE,
  equity_invested_musd      NUMBER(10,1),
  ownership_pct             NUMBER(5,1),
  status                    STRING,
  proceeds_returned_musd    NUMBER(10,1)  -- cash returned to the fund: recaps, refinancings, partial sales
);

INSERT INTO PORTFOLIO_COMPANIES VALUES
 ('Tessaline Health',     'Fund IV','Healthcare Services',              'US',          '2023-09-15',620,78,'Active',            260),
 ('Corvane Grid Services','Fund IV','Energy Transition & Infrastructure','US / Canada', '2024-02-20',540,65,'Partially realised',650),
 ('Pellucid Systems',     'Fund IV','Vertical Software',                'US',          '2025-11-10',480,71,'Active',              0),
 ('Ostrava Packaging',    'Fund IV','Industrial Services',              'Europe',      '2024-07-15',295,60,'Active',              0),
 ('Meridale Diagnostics', 'Fund IV','Healthcare Services',              'India',       '2026-05-20',310,62,'Active',              0);

-- ---------------------------------------------------------------------
-- 3. Company financials: one row per company per quarter (LTM figures)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE COMPANY_FINANCIALS (
  company_name              STRING,
  period                    STRING,
  quarter_end_date          DATE,
  ltm_revenue_musd          NUMBER(10,1),
  ltm_ebitda_musd           NUMBER(10,1),
  arr_musd                  NUMBER(10,1),  -- annual recurring revenue, software companies only
  net_debt_to_ebitda        NUMBER(5,1)
);

INSERT INTO COMPANY_FINANCIALS VALUES
 ('Tessaline Health',     '2025-Q4','2025-12-31', 540, 90,NULL,4.7),
 ('Tessaline Health',     '2026-Q1','2026-03-31', 553, 94,NULL,4.6),
 ('Tessaline Health',     '2026-Q2','2026-06-30', 568, 97,NULL,4.5),
 ('Tessaline Health',     '2026-Q3','2026-09-30', 585,101,NULL,4.4),
 ('Corvane Grid Services','2025-Q4','2025-12-31',1365,141,NULL,3.6),
 ('Corvane Grid Services','2026-Q1','2026-03-31',1390,146,NULL,3.9),
 ('Corvane Grid Services','2026-Q2','2026-06-30',1325,149,NULL,3.7),
 ('Corvane Grid Services','2026-Q3','2026-09-30',1310,152,NULL,3.6),
 ('Pellucid Systems',     '2025-Q4','2025-12-31', 132, 29, 145,6.0),
 ('Pellucid Systems',     '2026-Q1','2026-03-31', 140, 33, 152,5.8),
 ('Pellucid Systems',     '2026-Q2','2026-06-30', 150, 38, 164,5.5),
 ('Pellucid Systems',     '2026-Q3','2026-09-30', 158, 41, 172,5.2),
 ('Ostrava Packaging',    '2025-Q4','2025-12-31', 410, 58,NULL,4.8),
 ('Ostrava Packaging',    '2026-Q1','2026-03-31', 412, 59,NULL,4.7),
 ('Ostrava Packaging',    '2026-Q2','2026-06-30', 405, 56,NULL,5.0),
 ('Ostrava Packaging',    '2026-Q3','2026-09-30', 372, 47,NULL,5.9),
 ('Meridale Diagnostics', '2026-Q2','2026-06-30', 131, 34,NULL,2.1),
 ('Meridale Diagnostics', '2026-Q3','2026-09-30', 134, 35,NULL,2.0);

-- Quick checks
SELECT * FROM FUND_PERFORMANCE ORDER BY quarter_end_date;
SELECT SUM(distributions_musd) AS total_distributions,           -- expect 910
       (SELECT SUM(proceeds_returned_musd) FROM PORTFOLIO_COMPANIES) AS total_proceeds  -- expect 910
FROM FUND_PERFORMANCE;
