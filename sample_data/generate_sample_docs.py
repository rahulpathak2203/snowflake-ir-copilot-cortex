import os, csv
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

OUT = "."
os.makedirs(OUT, exist_ok=True)

FIRM = "Halvoran Ridge Capital"
FUND = "Halvoran Ridge Capital Partners IV, L.P."
NAVY = colors.HexColor("#14284B")
GOLD = colors.HexColor("#B08D3C")

ss = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=ss["Title"], textColor=NAVY, fontSize=20, leading=24, alignment=0, spaceAfter=6)
SUB = ParagraphStyle("SUB", parent=ss["Normal"], textColor=GOLD, fontSize=11, spaceAfter=14)
H2 = ParagraphStyle("H2", parent=ss["Heading2"], textColor=NAVY, fontSize=13, spaceBefore=12, spaceAfter=6)
H3 = ParagraphStyle("H3", parent=ss["Heading3"], textColor=NAVY, fontSize=11, spaceBefore=8, spaceAfter=4)
P = ParagraphStyle("P", parent=ss["Normal"], fontSize=10, leading=14, spaceAfter=7)
Q = ParagraphStyle("Q", parent=P, fontName="Helvetica-Bold", spaceBefore=6, spaceAfter=3)
B = ParagraphStyle("B", parent=P, leftIndent=12, bulletIndent=2, spaceAfter=3)

def footer(c, doc):
    c.saveState()
    c.setStrokeColor(GOLD); c.line(18*mm, 15*mm, 192*mm, 15*mm)
    c.setFont("Helvetica", 7.5); c.setFillColor(colors.grey)
    c.drawString(18*mm, 10*mm, f"{FIRM} | Confidential - Limited Partner use only")
    c.drawString(18*mm, 6.5*mm, "FICTIONAL SAMPLE DOCUMENT created for a demo project. Firm, fund, companies and figures are invented.")
    c.drawRightString(192*mm, 10*mm, f"Page {doc.page}")
    c.restoreState()

def table(rows, widths=None):
    t = Table(rows, colWidths=widths, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), NAVY), ("TEXTCOLOR", (0,0), (-1,0), colors.white),
        ("FONTNAME", (0,0), (-1,0), "Helvetica-Bold"), ("FONTSIZE", (0,0), (-1,-1), 8.8),
        ("GRID", (0,0), (-1,-1), 0.4, colors.HexColor("#C9CED6")),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, colors.HexColor("#F2F4F7")]),
        ("VALIGN", (0,0), (-1,-1), "TOP"), ("TOPPADDING", (0,0), (-1,-1), 4), ("BOTTOMPADDING", (0,0), (-1,-1), 4),
    ]))
    return [t, Spacer(1, 8)]

def para(text): return Paragraph(text, P)
def bullets(items): return [Paragraph(i, B, bulletText="\u2022") for i in items]

def build(fname, title, subtitle, story):
    doc = SimpleDocTemplate(os.path.join(OUT, fname), pagesize=A4, leftMargin=18*mm, rightMargin=18*mm,
                            topMargin=18*mm, bottomMargin=22*mm, title=title, author=FIRM)
    doc.build([Paragraph(title, H1), Paragraph(subtitle, SUB)] + story, onFirstPage=footer, onLaterPages=footer)

MANIFEST = []
def reg(fname, doc_type, quarter, sector, desc):
    MANIFEST.append(dict(file_name=fname, fund="Fund IV", doc_type=doc_type, period=quarter, sector=sector, description=desc))

# ---------------------------------------------------------------- 1. Fund overview
s = []
s.append(Paragraph("Firm at a glance", H2))
s.append(para(f"{FIRM} is an independent private markets manager founded in 2009 and headquartered in New York, with offices in London, Singapore and Mumbai. The firm manages approximately $24.8 billion of assets across three strategies: Private Equity, Infrastructure and Private Credit. The firm employs 162 people, including 58 investment professionals."))
s += table([["Strategy", "AUM ($bn)", "Funds", "Inception"],
            ["Private Equity (Flagship)", "14.6", "Funds I - IV", "2010"],
            ["Infrastructure", "6.1", "Infra I - II", "2016"],
            ["Private Credit", "4.1", "Direct Lending I - III", "2018"],
            ["Total", "24.8", "", ""]], [70*mm, 30*mm, 45*mm, 30*mm])
s.append(Paragraph("Fund IV summary", H2))
s += table([["Term", "Detail"],
            ["Fund", FUND],
            ["Vintage year", "2023 (first close June 2023)"],
            ["Final close", "March 2024"],
            ["Total commitments", "$6.5 billion (hard cap $7.0 billion)"],
            ["GP commitment", "2.5% of total commitments ($162.5 million)"],
            ["Target net returns", "Net IRR 15-18%; net TVPI 2.0x"],
            ["Investment period", "5 years from final close"],
            ["Fund term", "10 years, plus two 1-year extensions"],
            ["Target deal size", "Equity cheques of $250 million - $750 million"],
            ["Geography", "North America (~60%), Europe (~25%), India & Southeast Asia (~15%)"]], [45*mm, 130*mm])
s.append(Paragraph("Investment strategy", H2))
s.append(para("Fund IV makes control and significant-minority investments in upper mid-market companies with enterprise values between $750 million and $4 billion. The fund focuses on three sectors where the firm has built deep operating expertise: Healthcare Services, Energy Transition & Infrastructure Services, and Vertical Software. We seek businesses with recurring revenue, defensible market positions and clear paths to margin expansion through operational improvement."))
s.append(para("Our value-creation approach is led by the Halvoran Operating Group, a team of 14 former operators who work alongside management on pricing, procurement, digital transformation and talent. Every investment has a 100-day plan agreed with management before closing."))
s.append(Paragraph("Track record of predecessor funds (as of 30 June 2026)", H2))
s += table([["Fund", "Vintage", "Size ($bn)", "Net IRR", "Net TVPI", "DPI"],
            ["Fund I", "2010", "1.2", "19.4%", "2.4x", "2.4x"],
            ["Fund II", "2015", "2.8", "17.1%", "2.1x", "1.7x"],
            ["Fund III", "2019", "4.5", "14.6%", "1.6x", "0.6x"],
            ["Fund IV", "2023", "6.5", "13.4%", "1.31x", "0.18x"]])
s.append(Paragraph("Investment team", H2))
s += bullets(["<b>Marguerite Oyelaran</b>, Managing Partner and Co-Founder - Chair of the Investment Committee.",
              "<b>Daniel Krystof</b>, Co-Founder and Head of Private Equity.",
              "<b>Ananya Raghunathan</b>, Partner, Head of Asia and Healthcare Services.",
              "<b>Tobias Wendling</b>, Partner, Energy Transition & Infrastructure Services.",
              "<b>Priya Castellano</b>, Chief Financial Officer.",
              "<b>Felix Arendt</b>, Head of Investor Relations (ir@halvoranridge-demo.com)."])
s.append(para("The Investment Committee has five voting members. Investments require unanimous approval for deals above $500 million of equity and majority approval otherwise."))
build("01_Fund_IV_Overview.pdf", "Fund IV - Fund Overview", f"{FUND} | Investor presentation summary | September 2026", s)
reg("01_Fund_IV_Overview.pdf", "fund_overview", "2026-Q3", "All", "Firm overview, Fund IV terms, strategy, track record, team")

# ---------------------------------------------------------------- 2-5. Quarterly letters
quarters = [
    dict(q="Q4 2025", qd="31 December 2025", file="02_Fund_IV_Q4_2025_Investor_Letter.pdf", key="2025-Q4",
         irr="12.1%", tvpi="1.21x", dpi="0.08x", called="58%", nav="4,560", dist="0",
         macro="Q4 2025 ended a year in which financing markets reopened meaningfully. Leveraged loan spreads tightened by roughly 75 basis points over the year, which supported refinancing activity across the portfolio.",
         news=["Completed the acquisition of <b>Pellucid Systems</b>, a vertical software provider for specialty pharmacies, for an enterprise value of $1.1 billion. Fund IV invested $480 million of equity.",
               "<b>Corvane Grid Services</b> signed two new multi-year contracts with utilities in Texas and Ontario, increasing contracted backlog to $1.9 billion.",
               "<b>Tessaline Health</b> opened 11 new outpatient clinics, taking the network to 214 sites."],
         outlook="We expect to deploy a further $600-800 million in 2026, with an active pipeline in Indian healthcare services."),
    dict(q="Q1 2026", qd="31 March 2026", file="03_Fund_IV_Q1_2026_Investor_Letter.pdf", key="2026-Q1",
         irr="12.8%", tvpi="1.26x", dpi="0.10x", called="63%", nav="4,980", dist="130",
         macro="Public market volatility rose in March 2026, but private valuations in our sectors were stable. Healthcare services multiples held at around 13-14x EBITDA.",
         news=["Completed a $130 million dividend recapitalisation at <b>Corvane Grid Services</b>, our first distribution to Fund IV limited partners.",
               "<b>Tessaline Health</b> integrated the 2025 add-on acquisition of Brightwater Physio, delivering $9 million of run-rate cost synergies, ahead of the $7 million plan.",
               "Signed an agreement to invest in <b>Meridale Diagnostics</b>, a pathology lab network in Western India (closing expected Q2 2026)."],
         outlook="Our deployment pace remains on plan. We continue to see better entry valuations in Europe than in the US."),
    dict(q="Q2 2026", qd="30 June 2026", file="04_Fund_IV_Q2_2026_Investor_Letter.pdf", key="2026-Q2",
         irr="13.4%", tvpi="1.31x", dpi="0.18x", called="68%", nav="5,310", dist="520",
         macro="Rate cuts by major central banks during Q2 2026 improved exit conditions. M&A volumes in our target segment rose roughly 20% year on year.",
         news=["Closed the investment in <b>Meridale Diagnostics</b> ($310 million of equity for a 62% stake).",
               "Sold the Canadian field-services division of <b>Corvane Grid Services</b> to a strategic buyer for $520 million, a 2.6x gross multiple on attributed cost.",
               "<b>Pellucid Systems</b> grew annual recurring revenue (ARR) 31% year on year to $164 million, with net revenue retention of 118%."],
         outlook="With the investment period roughly half complete, Fund IV is 68% called. We expect to begin fundraising for Fund V in 2027."),
    dict(q="Q3 2026", qd="30 September 2026", file="05_Fund_IV_Q3_2026_Investor_Letter.pdf", key="2026-Q3",
         irr="14.0%", tvpi="1.36x", dpi="0.22x", called="72%", nav="5,620", dist="260",
         macro="Credit markets remained open in Q3 2026 and valuations were broadly flat. We remain cautious on businesses exposed to US healthcare reimbursement changes.",
         news=["<b>Tessaline Health</b> completed a refinancing that reduced its interest cost by 110 basis points and returned $260 million to the fund.",
               "<b>Pellucid Systems</b> launched an AI-assisted prior-authorisation module; 40 pharmacy chains signed up in the first 60 days.",
               "Wrote down <b>Ostrava Packaging</b> by 15% following the loss of a major customer contract. A new CEO was appointed in August 2026."],
         outlook="Fund IV is 72% called. We expect two more platform investments before the investment period ends."),
]
for d in quarters:
    s = []
    s.append(para("Dear Limited Partners,"))
    s.append(para(f"We are pleased to share the quarterly update for {FUND} for the quarter ended {d['qd']}. {d['macro']}"))
    s.append(Paragraph("Fund performance", H2))
    s += table([["Metric", d["q"]],
                ["Net IRR (since inception)", d["irr"]], ["Net TVPI", d["tvpi"]], ["DPI", d["dpi"]],
                ["Capital called (% of commitments)", d["called"]], ["Net asset value ($m)", d["nav"]],
                ["Distributions this quarter ($m)", d["dist"]]], [90*mm, 50*mm])
    s.append(Paragraph("Portfolio highlights", H2))
    s += bullets(d["news"])
    s.append(Paragraph("Portfolio summary", H2))
    s += table([["Company", "Sector", "Region", "Invested ($m)", "Status"],
                ["Tessaline Health", "Healthcare Services", "US", "620", "Active"],
                ["Corvane Grid Services", "Energy Transition & Infra", "US / Canada", "540", "Partially realised" if d["key"] in ("2026-Q2","2026-Q3") else "Active"],
                ["Pellucid Systems", "Vertical Software", "US", "480", "Active"],
                ["Ostrava Packaging", "Industrial Services", "Europe", "295", "Active"],
                ["Meridale Diagnostics", "Healthcare Services", "India", "310", "Active" if d["key"] in ("2026-Q2","2026-Q3") else "Signed"]])
    s.append(Paragraph("ESG update", H2))
    s.append(para("All portfolio companies reported emissions data for the period. Scope 1 and 2 emissions data are reviewed by an independent third party annually. No material ESG incidents were reported during the quarter."))
    s.append(Paragraph("Outlook", H2))
    s.append(para(d["outlook"]))
    s.append(para("As always, please contact Felix Arendt in Investor Relations with any questions."))
    s.append(para("Sincerely,<br/>Marguerite Oyelaran, Managing Partner<br/>Daniel Krystof, Head of Private Equity"))
    build(d["file"], f"Fund IV - {d['q']} Investor Letter", f"{FUND} | Quarter ended {d['qd']}", s)
    reg(d["file"], "quarterly_letter", d["key"], "All", f"{d['q']} performance, portfolio highlights, outlook")

# ---------------------------------------------------------------- 6. ESG policy
s = []
s.append(Paragraph("1. Purpose and scope", H2))
s.append(para(f"This policy sets out how {FIRM} integrates environmental, social and governance (ESG) factors across the investment lifecycle. It applies to all funds and strategies managed by the firm. The policy was approved by the Management Committee in January 2026 and is reviewed annually."))
s.append(Paragraph("2. Governance", H2))
s.append(para("The ESG Committee is chaired by the Managing Partner and includes the Head of ESG (Sofia Lindqvist), the CFO and two investment partners. It meets quarterly and reports to the Management Committee. ESG performance is a component of annual compensation reviews for all investment professionals."))
s.append(Paragraph("3. Exclusion list", H2))
s.append(para("The firm will not invest in companies that derive more than 10% of revenue from:"))
s += bullets(["Thermal coal mining or coal-fired power generation", "Controversial weapons (cluster munitions, anti-personnel mines, chemical or biological weapons)",
              "Tobacco manufacturing", "Adult entertainment", "Predatory lending"])
s.append(Paragraph("4. Investment process", H2))
s.append(para("<b>Pre-investment:</b> Every opportunity is screened against the exclusion list. Deals that pass screening receive ESG due diligence using the SASB framework for the relevant industry. Material findings are included in the Investment Committee memo."))
s.append(para("<b>Ownership:</b> Each portfolio company sets an ESG action plan within 12 months of acquisition. Companies report annually on a core set of 22 KPIs, including greenhouse gas emissions, employee turnover, board diversity and cybersecurity incidents."))
s.append(para("<b>Exit:</b> ESG improvements are documented in vendor due diligence materials."))
s.append(Paragraph("5. Climate", H2))
s.append(para("The firm is aligned with TCFD recommendations and publishes an annual climate report. The firm's target is for 75% of portfolio companies (by invested capital) to have science-based emissions targets by 2030. As of 2025, 41% of Fund IV invested capital met this criterion."))
s.append(Paragraph("6. Diversity, equity and inclusion", H2))
s.append(para("The firm targets at least 30% women on portfolio company boards within two years of investment. As of 31 December 2025, women held 34% of Fund IV portfolio company board seats and 38% of the firm's own investment team roles."))
s.append(Paragraph("7. Reporting to investors", H2))
s.append(para("ESG data is reported to limited partners in quarterly letters and an annual ESG report. The firm completes the ILPA ESG Data Convergence Initiative template annually. ESG incidents rated 'severe' are reported to the LP Advisory Committee within 10 business days."))
build("06_ESG_Responsible_Investment_Policy.pdf", "ESG & Responsible Investment Policy", f"{FIRM} | Version 4.0 | Effective January 2026", s)
reg("06_ESG_Responsible_Investment_Policy.pdf", "policy_esg", "2026", "All", "ESG governance, exclusions, climate targets, DEI, reporting")

# ---------------------------------------------------------------- 7. Valuation policy
s = []
s.append(Paragraph("1. Objective", H2))
s.append(para("Investments are valued at fair value in accordance with US GAAP (ASC 820) and the International Private Equity and Venture Capital (IPEV) Valuation Guidelines. Valuations are prepared quarterly."))
s.append(Paragraph("2. Valuation governance", H2))
s.append(para("The Valuation Committee is chaired by the CFO, Priya Castellano, and includes the Chief Compliance Officer and one partner not involved in the investments being valued. Deal teams prepare valuations but do not approve them. An independent valuation firm reviews 100% of portfolio companies at year end and at least 30% (by NAV) in each interim quarter."))
s.append(Paragraph("3. Methodologies", H2))
s += table([["Method", "When used", "Weighting (typical)"],
            ["Comparable public company multiples", "Primary method for most mature companies", "50-70%"],
            ["Precedent transactions", "Where relevant recent M&A is available", "15-30%"],
            ["Discounted cash flow", "Infrastructure assets with contracted cash flows", "0-100%"],
            ["Cost / recent transaction", "Within 12 months of acquisition", "Up to 100%"]], [65*mm, 75*mm, 35*mm])
s.append(Paragraph("4. Key controls", H2))
s += bullets(["Changes in a company's valuation above 10% quarter on quarter require a written explanation to the Valuation Committee.",
              "Discounts to public comparables are applied for size and liquidity, typically 10-25%.",
              "Write-downs are recognised promptly; write-ups require evidence such as a third-party offer or sustained outperformance over two quarters.",
              "The fund's auditor, a Big Four firm, reviews valuation procedures annually."])
s.append(Paragraph("5. Disclosure", H2))
s.append(para("Limited partners receive company-level valuations, methodology used and key multiples in each quarterly report. Methodology changes are disclosed with an explanation of their impact."))
build("07_Valuation_Policy.pdf", "Valuation Policy", f"{FIRM} | Version 3.2 | Effective January 2025", s)
reg("07_Valuation_Policy.pdf", "policy_valuation", "2025", "All", "Fair value methods, governance, controls, disclosure")

# ---------------------------------------------------------------- 8. Fees & expenses
s = []
s.append(para(f"This summary describes the principal economic terms of {FUND}. It is qualified in its entirety by the Limited Partnership Agreement (LPA) and the Private Placement Memorandum."))
s.append(Paragraph("Management fee", H2))
s += table([["Period", "Rate", "Basis"],
            ["Investment period (5 years)", "1.50% per annum", "Total commitments"],
            ["Post-investment period", "1.25% per annum", "Net invested capital"],
            ["Commitments of $250m or more", "1.25% / 1.00%", "Same bases as above"],
            ["First-close investors", "10 bps discount", "Applies for the life of the fund"]], [65*mm, 45*mm, 65*mm])
s.append(Paragraph("Carried interest and waterfall", H2))
s.append(para("The general partner receives carried interest of 20% of profits, subject to an 8% annual compounding preferred return. The fund uses a whole-of-fund (European) waterfall with a 100% GP catch-up. A clawback applies at the end of the fund term, net of taxes, and is guaranteed by the senior partners."))
s += bullets(["Step 1: 100% to LPs until return of contributed capital.", "Step 2: 100% to LPs until an 8% preferred return.",
              "Step 3: 100% to the GP until it has received 20% of cumulative profits (catch-up).", "Step 4: 80% to LPs / 20% to the GP thereafter."])
s.append(Paragraph("Fee offsets", H2))
s.append(para("100% of transaction, monitoring, director and break-up fees received by the firm or its affiliates are offset against the management fee."))
s.append(Paragraph("Fund expenses", H2))
s += table([["Expense", "Borne by", "Cap / note"],
            ["Organisational expenses", "Fund", "Capped at $4.0 million; excess borne by the GP"],
            ["Broken-deal expenses", "Fund", "Allocated pro rata with co-investors"],
            ["Audit, tax and fund administration", "Fund", "No cap"],
            ["Placement agent fees", "GP", "100% borne by the GP"],
            ["Firm overhead and salaries", "GP", "Not charged to the fund"],
            ["Operating Group (portfolio support)", "Portfolio companies", "Capped at $1.5m per company per year"]], [60*mm, 35*mm, 80*mm])
s.append(Paragraph("Other key terms", H2))
s += bullets(["Key person: triggered if two of Marguerite Oyelaran, Daniel Krystof and Ananya Raghunathan cease to devote substantially all of their time to the firm. Suspends the investment period.",
              "No-fault removal of the GP: requires a 75% in-interest vote of limited partners.",
              "LP Advisory Committee: 7-11 members drawn from the largest investors; reviews conflicts of interest.",
              "Recycling: up to 20% of commitments may be recycled from realisations within 18 months of investment."])
build("08_Fund_IV_Fee_and_Expense_Summary.pdf", "Fund IV - Summary of Fees & Expenses", f"{FUND} | Extract from Private Placement Memorandum", s)
reg("08_Fund_IV_Fee_and_Expense_Summary.pdf", "fees_terms", "2023", "All", "Management fee, carry, waterfall, offsets, expenses, key person")

# ---------------------------------------------------------------- 9. Portfolio company profiles
cos = [
 dict(n="Tessaline Health", sec="Healthcare Services", hq="Nashville, Tennessee", date="September 2023", eq="620", own="78%",
      desc="Tessaline operates 214 outpatient physical therapy and musculoskeletal clinics across 9 US states.",
      thesis=["Fragmented market: the top 5 providers hold under 20% share.", "Demographic tailwind from an ageing population.", "Buy-and-build: 4 add-on acquisitions completed since entry."],
      fin=[["", "At entry (FY2023)", "LTM Sep 2026"], ["Revenue ($m)", "410", "585"], ["EBITDA ($m)", "62", "101"], ["EBITDA margin", "15.1%", "17.3%"], ["Net debt / EBITDA", "5.2x", "4.4x"]],
      risks="US reimbursement rate changes; clinician labour shortages."),
 dict(n="Corvane Grid Services", sec="Energy Transition & Infrastructure Services", hq="Houston, Texas", date="February 2024", eq="540", own="65%",
      desc="Corvane provides engineering, construction and maintenance services for electricity transmission and distribution networks in North America.",
      thesis=["Grid investment needed for renewables and data-centre demand.", "Multi-year utility contracts give high revenue visibility.", "Sold Canadian division in Q2 2026 for $520m (2.6x gross MOIC)."],
      fin=[["", "At entry (FY2023)", "LTM Sep 2026"], ["Revenue ($m)", "1,240", "1,310"], ["EBITDA ($m)", "118", "152"], ["Contracted backlog ($bn)", "1.3", "1.9"], ["Net debt / EBITDA", "4.0x", "3.6x"]],
      risks="Project execution and cost overruns; dependence on utility capex cycles."),
 dict(n="Pellucid Systems", sec="Vertical Software", hq="Boston, Massachusetts", date="November 2025", eq="480", own="71%",
      desc="Pellucid provides cloud software for specialty pharmacies, covering dispensing, compliance, patient adherence and prior authorisation.",
      thesis=["Mission-critical software with gross revenue retention above 95%.", "Product expansion into AI-assisted prior authorisation.", "Pricing upside from a move to module-based packaging."],
      fin=[["", "At entry (FY2025)", "LTM Sep 2026"], ["ARR ($m)", "141", "172"], ["ARR growth", "27%", "31%"], ["Net revenue retention", "112%", "118%"], ["EBITDA margin", "22%", "26%"]],
      risks="Competition from larger healthcare IT vendors; data privacy regulation (HIPAA)."),
 dict(n="Meridale Diagnostics", sec="Healthcare Services", hq="Pune, India", date="May 2026", eq="310", own="62%",
      desc="Meridale operates 46 pathology labs and over 900 sample collection centres across Maharashtra and Gujarat.",
      thesis=["Indian diagnostics market growing at around 12% a year.", "Shift from unorganised to organised labs.", "Founder family retains 30%, keeping management aligned."],
      fin=[["", "At entry (FY2026)", "LTM Sep 2026"], ["Revenue ($m)", "128", "134"], ["EBITDA ($m)", "33", "35"], ["Tests performed (m / yr)", "21", "22"], ["Net debt / EBITDA", "2.1x", "2.0x"]],
      risks="Price competition from national chains; regulatory price caps on tests."),
]
s = []
for i, c in enumerate(cos):
    if i: s.append(PageBreak())
    s.append(Paragraph(c["n"], H2))
    s += table([["Sector", "Headquarters", "Investment date", "Fund IV equity ($m)", "Ownership"],
                [c["sec"], c["hq"], c["date"], c["eq"], c["own"]]], [48*mm, 38*mm, 30*mm, 34*mm, 24*mm])
    s.append(para(c["desc"]))
    s.append(Paragraph("Investment thesis", H3)); s += bullets(c["thesis"])
    s.append(Paragraph("Key financials", H3)); s += table(c["fin"], [60*mm, 45*mm, 45*mm])
    s.append(Paragraph("Key risks", H3)); s.append(para(c["risks"]))
build("09_Fund_IV_Portfolio_Company_Profiles.pdf", "Fund IV - Portfolio Company Profiles", f"{FUND} | As of 30 September 2026", s)
reg("09_Fund_IV_Portfolio_Company_Profiles.pdf", "portfolio_profiles", "2026-Q3", "Healthcare; Infrastructure; Software", "Profiles of Tessaline, Corvane, Pellucid, Meridale")

# ---------------------------------------------------------------- 10. DDQ
qa = [
 ("Organisation", [
  ("1.1 Describe the ownership structure of the firm.", "The firm is 100% employee-owned. The two co-founders hold 46% combined; the remaining 54% is held by 19 partners. No external party holds an economic interest in the management company."),
  ("1.2 Has the firm experienced any senior departures in the last three years?", "One partner, the former Head of Europe, retired in 2024 under a planned succession. His responsibilities passed to Tobias Wendling. There were no other senior departures."),
  ("1.3 Is the firm, or any employee, subject to litigation or regulatory action?", "No. The firm is registered with the US SEC as an investment adviser. Its most recent SEC examination, in 2024, closed with no deficiencies requiring remediation.")]),
 ("Investment process", [
  ("2.1 Describe the investment decision-making process.", "Deals pass through three Investment Committee stages: screening, preliminary approval and final approval. The Committee has five voting members. Equity cheques above $500 million require a unanimous vote."),
  ("2.2 How are deals allocated between Fund IV and co-investors?", "Fund IV has priority on all deals within its strategy. Co-investment is offered when an equity cheque exceeds 15% of fund commitments. Co-investment is offered to LPs pro rata to commitment size and is typically fee-free with no carried interest.")]),
 ("Risk management and operations", [
  ("3.1 How does the firm manage cybersecurity risk?", "The firm follows the NIST Cybersecurity Framework, conducts annual penetration testing with an external provider and requires multi-factor authentication for all systems. Portfolio companies complete an annual cyber maturity assessment."),
  ("3.2 Who is the fund administrator and auditor?", "Fund administration is outsourced to an independent third-party administrator. The fund is audited annually by a Big Four accounting firm. Audited financial statements are delivered within 120 days of year end."),
  ("3.3 Does the fund use leverage at fund level?", "Fund IV uses a subscription credit facility of up to 20% of commitments. Borrowings are repaid within 180 days. Net IRR is reported both with and without the effect of the facility.")]),
 ("ESG", [
  ("4.1 Is the firm a signatory to any responsible investment initiatives?", "Yes. The firm has been a signatory to the UN-supported Principles for Responsible Investment (PRI) since 2017, and supports the ILPA ESG Data Convergence Initiative."),
  ("4.2 How are ESG risks considered in due diligence?", "See the ESG & Responsible Investment Policy. All deals are screened against the exclusion list and receive SASB-based ESG due diligence. Material findings are presented to the Investment Committee.")]),
 ("Reporting", [
  ("5.1 What reporting do LPs receive and when?", "Quarterly reports within 60 days of quarter end (90 days for Q4), including ILPA-template fee and expense reporting. An annual meeting is held each May. Capital call notices are issued with at least 10 business days' notice."),
  ("5.2 Do you report fund-level net IRR with and without the credit facility?", "Yes. As of 30 June 2026, Fund IV's net IRR was 13.4% with the facility and 12.6% without it.")]),
]
s = [para("This document contains the firm's standard responses to the ILPA Due Diligence Questionnaire, as provided to prospective investors in Fund IV. Responses are current as of 30 June 2026 unless otherwise stated.")]
for sec, items in qa:
    s.append(Paragraph(sec, H2))
    for q, a in items:
        s.append(Paragraph(q, Q)); s.append(para(a))
build("10_Due_Diligence_Questionnaire_Responses.pdf", "Due Diligence Questionnaire - Standard Responses", f"{FIRM} | Prepared for Fund IV investors | July 2026", s)
reg("10_Due_Diligence_Questionnaire_Responses.pdf", "ddq", "2026-Q2", "All", "Standard ILPA DDQ answers: organisation, process, risk, ESG, reporting")

with open(os.path.join(OUT, "document_manifest.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(MANIFEST[0].keys())); w.writeheader(); w.writerows(MANIFEST)
print("done", len(MANIFEST))
