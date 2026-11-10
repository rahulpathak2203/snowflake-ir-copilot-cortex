-- =====================================================================
-- Semantic view: tells Cortex Analyst what the fund tables mean
-- Prerequisite: 02_fund_data.sql
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE IR_WH;
USE SCHEMA IR_COPILOT.FUND_DOCS;

CREATE OR REPLACE SEMANTIC VIEW IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV

  TABLES (
    fund_perf AS IR_COPILOT.FUND_DOCS.FUND_PERFORMANCE
      PRIMARY KEY (fund_name, period)
      WITH SYNONYMS ('fund performance', 'fund returns', 'quarterly performance')
      COMMENT = 'Fund IV performance, one row per quarter. Amounts in USD millions.',
    companies AS IR_COPILOT.FUND_DOCS.PORTFOLIO_COMPANIES
      PRIMARY KEY (company_name)
      WITH SYNONYMS ('portfolio', 'portfolio companies', 'investments', 'holdings')
      COMMENT = 'One row per portfolio company with investment details. Amounts in USD millions.',
    financials AS IR_COPILOT.FUND_DOCS.COMPANY_FINANCIALS
      PRIMARY KEY (company_name, period)
      WITH SYNONYMS ('company financials', 'operating metrics', 'company KPIs')
      COMMENT = 'Last-twelve-months (LTM) financials per portfolio company per quarter. Amounts in USD millions.'
  )

  RELATIONSHIPS (
    financials_to_companies AS financials (company_name) REFERENCES companies
  )

  FACTS (
    fund_perf.net_irr_value         AS net_irr_pct,
    fund_perf.net_irr_ex_value      AS net_irr_ex_facility_pct,
    fund_perf.tvpi_value            AS net_tvpi,
    fund_perf.dpi_value             AS dpi,
    fund_perf.pct_called_value      AS pct_capital_called,
    fund_perf.capital_called_value  AS capital_called_musd,
    fund_perf.nav_value             AS nav_musd,
    fund_perf.distributions_value   AS distributions_musd,
    fund_perf.commitments_value     AS commitments_musd,

    companies.equity_value          AS equity_invested_musd,
    companies.ownership_value       AS ownership_pct,
    companies.proceeds_value        AS proceeds_returned_musd,

    financials.revenue_value        AS ltm_revenue_musd,
    financials.ebitda_value         AS ltm_ebitda_musd,
    financials.arr_value            AS arr_musd,
    financials.leverage_value       AS net_debt_to_ebitda
  )

  DIMENSIONS (
    fund_perf.fund_name             AS fund_name
      WITH SYNONYMS = ('fund')
      COMMENT = 'Fund name, e.g. Fund IV',
    fund_perf.period                AS period
      WITH SYNONYMS = ('quarter', 'reporting period')
      COMMENT = 'Reporting quarter in the format YYYY-QN, e.g. 2026-Q3. The latest quarter is the most recent period.',
    fund_perf.quarter_end_date      AS quarter_end_date
      COMMENT = 'Last day of the reporting quarter',

    companies.company_name          AS company_name
      WITH SYNONYMS = ('company', 'portfolio company', 'investment')
      COMMENT = 'Portfolio company name',
    companies.sector                AS sector
      WITH SYNONYMS = ('industry')
      COMMENT = 'Sector: Healthcare Services, Energy Transition & Infrastructure, Vertical Software, Industrial Services',
    companies.region                AS region
      WITH SYNONYMS = ('geography', 'country')
      COMMENT = 'Where the company operates: US, US / Canada, Europe, India',
    companies.status                AS status
      COMMENT = 'Active or Partially realised (some assets sold), as of 2026-Q3',
    companies.investment_date       AS investment_date
      COMMENT = 'Date the fund invested',
    companies.investment_year       AS YEAR(investment_date)
      COMMENT = 'Year the fund invested',

    financials.fin_period           AS period
      WITH SYNONYMS = ('quarter')
      COMMENT = 'Quarter of the financial figures, format YYYY-QN',
    financials.fin_quarter_end_date AS quarter_end_date
      COMMENT = 'Last day of the quarter for the financial figures'
  )

  METRICS (
    -- Fund level (one row per quarter, so grouped by period these return that quarter's value)
    fund_perf.net_irr               AS AVG(fund_perf.net_irr_value)
      WITH SYNONYMS = ('IRR', 'internal rate of return', 'return')
      COMMENT = 'Net IRR in percent since inception, including the subscription credit facility',
    fund_perf.net_irr_ex_facility   AS AVG(fund_perf.net_irr_ex_value)
      WITH SYNONYMS = ('IRR without credit facility', 'unlevered IRR')
      COMMENT = 'Net IRR in percent excluding the subscription credit facility. Only disclosed for some quarters; NULL means not disclosed.',
    fund_perf.net_tvpi              AS AVG(fund_perf.tvpi_value)
      WITH SYNONYMS = ('TVPI', 'total value to paid-in', 'multiple')
      COMMENT = 'Net total value to paid-in multiple',
    fund_perf.dpi                   AS AVG(fund_perf.dpi_value)
      WITH SYNONYMS = ('DPI', 'distributions to paid-in')
      COMMENT = 'Distributions to paid-in capital multiple',
    fund_perf.pct_capital_called    AS AVG(fund_perf.pct_called_value)
      WITH SYNONYMS = ('percent called', 'deployment')
      COMMENT = 'Capital called as a percent of commitments',
    fund_perf.nav                   AS SUM(fund_perf.nav_value)
      WITH SYNONYMS = ('NAV', 'net asset value')
      COMMENT = 'Net asset value in USD millions. Only meaningful for a single quarter; do not add across quarters.',
    fund_perf.total_distributions   AS SUM(fund_perf.distributions_value)
      WITH SYNONYMS = ('distributions', 'cash returned to LPs')
      COMMENT = 'Distributions to LPs in USD millions; summing across quarters gives cumulative distributions',

    -- Company level
    companies.total_equity_invested AS SUM(companies.equity_value)
      WITH SYNONYMS = ('invested capital', 'amount invested', 'cost')
      COMMENT = 'Equity invested by the fund in USD millions',
    companies.total_proceeds        AS SUM(companies.proceeds_value)
      WITH SYNONYMS = ('proceeds', 'cash returned', 'realisations')
      COMMENT = 'Cash returned to the fund from companies (recaps, refinancings, partial sales) in USD millions',
    companies.company_count         AS COUNT(companies.company_name)
      WITH SYNONYMS = ('number of companies')
      COMMENT = 'Number of portfolio companies',
    companies.avg_ownership         AS AVG(companies.ownership_value)
      COMMENT = 'Average ownership stake in percent',

    -- Company financials (LTM)
    financials.ltm_revenue          AS SUM(financials.revenue_value)
      WITH SYNONYMS = ('revenue', 'sales')
      COMMENT = 'Last-twelve-months revenue in USD millions. Filter to one quarter before adding across companies.',
    financials.ltm_ebitda           AS SUM(financials.ebitda_value)
      WITH SYNONYMS = ('EBITDA', 'earnings')
      COMMENT = 'Last-twelve-months EBITDA in USD millions. Filter to one quarter before adding across companies.',
    financials.ebitda_margin_pct    AS SUM(financials.ebitda_value) / NULLIF(SUM(financials.revenue_value), 0) * 100
      WITH SYNONYMS = ('margin', 'EBITDA margin')
      COMMENT = 'LTM EBITDA as a percent of LTM revenue',
    financials.arr                  AS SUM(financials.arr_value)
      WITH SYNONYMS = ('ARR', 'annual recurring revenue')
      COMMENT = 'Annual recurring revenue in USD millions (software companies only)',
    financials.leverage             AS AVG(financials.leverage_value)
      WITH SYNONYMS = ('net debt to EBITDA', 'leverage ratio', 'debt')
      COMMENT = 'Net debt divided by LTM EBITDA'
  )

  COMMENT = 'Halvoran Ridge Capital Fund IV: fund performance, portfolio companies and company financials';

-- Check it
DESCRIBE SEMANTIC VIEW IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV;

-- Query it directly (no AI) to confirm it works
SELECT * FROM SEMANTIC_VIEW(
  IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV
  DIMENSIONS fund_perf.period
  METRICS fund_perf.net_irr, fund_perf.total_distributions
)
ORDER BY period;
