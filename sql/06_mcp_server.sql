-- =====================================================================
-- Halvoran Ridge Capital - expose IR Copilot through a Snowflake-managed MCP server
-- Lets external AI assistants (Claude, ChatGPT, Cursor) use the agent, search and analyst as tools.
-- Prerequisites: 01-04 already run (search service, semantic view, agent exist).
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1. Create the MCP server (lists which tools are exposed)
--   Tool names use hyphens: underscores can cause connection issues.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;
USE WAREHOUSE IR_WH;

CREATE OR REPLACE MCP SERVER IR_COPILOT.FUND_DOCS.IR_COPILOT_MCP
  FROM SPECIFICATION $$
  tools:
    - title: "IR Copilot agent"
      name: "ir-copilot-agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "IR_COPILOT.FUND_DOCS.IR_COPILOT_AGENT"
      description: "Answers investor questions about Halvoran Ridge Capital Fund IV using fund documents and fund data, with citations. Use this for most questions."
    - title: "Fund document search"
      name: "fund-docs-search"
      type: "CORTEX_SEARCH_SERVICE_QUERY"
      identifier: "IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH"
      description: "Searches Fund IV investor letters, fee and expense terms, ESG and valuation policies, portfolio company profiles and DDQ responses."
    - title: "Fund data analyst"
      name: "fund-data-analyst"
      type: "CORTEX_ANALYST_MESSAGE"
      identifier: "IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV"
      description: "Answers numeric questions with SQL: quarterly fund performance (IRR, TVPI, DPI, NAV, distributions), portfolio companies and company financials."
  $$;

SHOW MCP SERVERS IN SCHEMA IR_COPILOT.FUND_DOCS;

-- ---------------------------------------------------------------------
-- STEP 2. A dedicated, least-privilege role for MCP access
--   OAuth blocks powerful roles like ACCOUNTADMIN by default, so external
--   assistants connect with this narrow role instead.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS IR_MCP_ROLE;

-- Cortex features
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER       TO ROLE IR_MCP_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE IR_MCP_ROLE;

-- Compute and containers
GRANT USAGE ON WAREHOUSE IR_WH                  TO ROLE IR_MCP_ROLE;
GRANT USAGE ON DATABASE  IR_COPILOT             TO ROLE IR_MCP_ROLE;
GRANT USAGE ON SCHEMA    IR_COPILOT.FUND_DOCS   TO ROLE IR_MCP_ROLE;

-- The MCP server itself (access to the server does NOT unlock its tools)
GRANT USAGE ON MCP SERVER IR_COPILOT.FUND_DOCS.IR_COPILOT_MCP TO ROLE IR_MCP_ROLE;

-- Each tool's underlying object
GRANT USAGE  ON AGENT                 IR_COPILOT.FUND_DOCS.IR_COPILOT_AGENT  TO ROLE IR_MCP_ROLE;
GRANT USAGE  ON CORTEX SEARCH SERVICE IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH  TO ROLE IR_MCP_ROLE;
GRANT SELECT ON SEMANTIC VIEW         IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV TO ROLE IR_MCP_ROLE;
GRANT SELECT ON TABLE IR_COPILOT.FUND_DOCS.FUND_PERFORMANCE    TO ROLE IR_MCP_ROLE;
GRANT SELECT ON TABLE IR_COPILOT.FUND_DOCS.PORTFOLIO_COMPANIES TO ROLE IR_MCP_ROLE;
GRANT SELECT ON TABLE IR_COPILOT.FUND_DOCS.COMPANY_FINANCIALS  TO ROLE IR_MCP_ROLE;
GRANT READ   ON STAGE IR_COPILOT.FUND_DOCS.FUND_PDFS           TO ROLE IR_MCP_ROLE;  -- PDF links in citations

-- Give the role to your user, and make it the default so OAuth sessions use it
SELECT CURRENT_USER();   -- your user name, use it below
GRANT ROLE IR_MCP_ROLE TO USER <your_snowflake_user>;
ALTER USER <your_snowflake_user> SET DEFAULT_ROLE = 'IR_MCP_ROLE' DEFAULT_WAREHOUSE = 'IR_WH';
-- To restore later:  ALTER USER <your_snowflake_user> SET DEFAULT_ROLE = 'ACCOUNTADMIN';

-- ---------------------------------------------------------------------
-- STEP 3. OAuth integration so Claude (claude.ai / Claude Desktop) can sign in
-- ---------------------------------------------------------------------
CREATE OR REPLACE SECURITY INTEGRATION IR_MCP_OAUTH_CLAUDE
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'PUBLIC'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_USE_SECONDARY_ROLES = NONE
  ALLOWED_ROLES_LIST = ('IR_MCP_ROLE');

-- Alternative for clients that store a secret (e.g. Cursor, VS Code):
--   same statement with OAUTH_CLIENT_TYPE = 'CONFIDENTIAL' and that client's redirect URI.

-- ---------------------------------------------------------------------
-- STEP 4. Get the OAuth client ID (and secret, if one is issued)
--   The integration name must be in UPPERCASE here.
-- ---------------------------------------------------------------------
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('IR_MCP_OAUTH_CLAUDE');

-- ---------------------------------------------------------------------
-- STEP 5. Your MCP endpoint URL (paste into the client):
--   https://<account_url>/api/v2/databases/IR_COPILOT/schemas/FUND_DOCS/mcp-servers/IR_COPILOT_MCP
--   <account_url> is the host from your FILE_URL column, e.g. xxxxx.<region>.snowflakecomputing.com
--
-- STEP 6. In Claude: Settings -> Connectors -> Add custom connector
--   Name: Snowflake IR Copilot | URL: the endpoint above
--   Advanced settings: OAuth client ID (and secret) from STEP 4
--   Click Add -> sign in to Snowflake -> approve. Then ask, for example:
--     "Use the IR Copilot to explain why Ostrava was written down and how its EBITDA trended."
-- ---------------------------------------------------------------------
