-- =====================================================================
-- Halvoran Ridge Capital - IR Copilot Cortex Agent
-- Two tools: Cortex Search (documents) + Cortex Analyst (numbers)
-- Run order: 01_search_pipeline.sql -> 02_fund_data.sql -> 03_semantic_view.sql -> this file
-- Change the agent name/location below to match yours if different.
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE IR_WH;

CREATE OR REPLACE AGENT IR_COPILOT.FUND_DOCS.IR_COPILOT_AGENT
  COMMENT = 'Investor relations assistant: fund documents (Cortex Search) + fund data (Cortex Analyst)'
  PROFILE = '{"display_name": "IR Copilot"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
instructions:
  system: |
    You are an investor relations assistant for Halvoran Ridge Capital, helping LPs and IR staff with questions about Fund IV.
    You have two sources: the fund's documents (fund_docs_search) and the fund's structured data (fund_data_analyst).
    Answer ONLY from what these tools return. Always cite the source document for facts from documents.
  orchestration: |
    Choose tools by the kind of question:
    - fund_data_analyst: numbers, trends, totals, rankings and comparisons - fund IRR, TVPI, DPI, NAV, capital called and
      distributions by quarter; portfolio company equity invested, ownership, sector, region, status and proceeds returned;
      company LTM revenue, EBITDA, EBITDA margin, ARR and leverage by quarter.
    - fund_docs_search: explanations, reasons, events and wording - why something happened, fund terms and LPA clauses
      (e.g. key person), fees and carried interest, ESG and valuation policies, DDQ answers, letter commentary.
    - Use BOTH when a question asks for numbers and the reason behind them (e.g. "why was X written down and how have its
      financials changed?"). Get the figures from fund_data_analyst and the explanation from fund_docs_search.
    For "latest" or "current" figures use the most recent quarter. Use search filters on doc_type or period when the question names them.
  response: |
    Be concise and factual. Give numbers with units (USD millions, %, x) and the quarter they refer to.
    When you cannot find a clear answer, say what is missing - do not invent information - and suggest contacting Investor Relations.
    Do not offer to set up automations, send emails, or take any actions - you can only answer questions.
  sample_questions:
    - question: "How has Fund IV's net IRR changed over the last four quarters?"
    - question: "Why was Ostrava Packaging written down, and how have its revenue and EBITDA trended?"
    - question: "How much has Fund IV invested in healthcare companies?"
    - question: "Who triggers the key person clause and what happens if it is triggered?"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: fund_data_analyst
      description: "Answers numeric questions with SQL over Fund IV structured data: quarterly fund performance (IRR, TVPI, DPI, NAV, capital called, distributions), portfolio companies (sector, region, equity invested, ownership, status, proceeds returned) and quarterly company financials (LTM revenue, EBITDA, margin, ARR, leverage)."
  - tool_spec:
      type: cortex_search
      name: fund_docs_search
      description: "Searches Halvoran Ridge Capital fund documents: quarterly investor letters, fee and expense summary (LPA terms), valuation policy, ESG policy, portfolio company profiles and DDQ responses. Filterable by fund, doc_type, period, sector."
tool_resources:
  fund_data_analyst:
    semantic_view: IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV
    execution_environment:          # warehouse that runs the SQL Cortex Analyst generates
      type: warehouse
      warehouse: IR_WH
  fund_docs_search:
    search_service: IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH
    id_column: chunk_uid
    title_column: file_name
    max_results: 5
    stage_path: "@IR_COPILOT.FUND_DOCS.FUND_PDFS"   # lets citations link to the original PDF
    relative_path_column: file_name
$$;

-- Check it
DESCRIBE AGENT IR_COPILOT.FUND_DOCS.IR_COPILOT_AGENT;

-- CREATE OR REPLACE drops existing grants on the agent.
-- If you've set up MCP (06_mcp_server.sql), give the MCP role access again:
GRANT USAGE ON AGENT IR_COPILOT.FUND_DOCS.IR_COPILOT_AGENT TO ROLE IR_MCP_ROLE;
