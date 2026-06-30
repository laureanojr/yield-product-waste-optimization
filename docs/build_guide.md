# Yield & Production Waste Optimization — The Complete Build Guide

*A plain-English walkthrough of the entire project, from empty folder to a live portfolio piece. Each step tells you what to do, why it matters, what you should have afterward, and how to explain it like a human.*

---

## The story this project tells

Before any code, hold the story in your head — because this is what you'll explain in interviews:

> "I'm a baker. Every day I watch the tension between making too much (waste) and too little (lost sales). I used two years of real bakery sales data to understand *when* and *what* customers actually buy, so production can be planned on evidence instead of gut feel. Then I built a simulated production system to show how I'd extend that analysis into a real plant's waste and machine data."

Everything below is just the detailed path that delivers that story.

### One thing to be crystal-clear about: this project has two parts

- **Part 1 — Real sales analysis.** Built on genuine data. **This is the only part that supports business conclusions.** Every insight, finding, and recommendation comes from here.
- **Part 2 — Synthetic manufacturing simulation.** Built on data you generate. It demonstrates *how* you'd analyze production and waste — it does **not** produce real findings.

Keep this line ready for interviews: *"Only Part 1 supports conclusions; Part 2 shows my engineering approach."* Blurring the two is the fastest way to lose a data-literate interviewer's trust; stating it plainly earns it.

**How to read each step:**
- **Do** — the action, in plain terms.
- **Why it matters** — the reason it earns its place.
- **You'll have after** — the concrete result.
- **Say it simply** — how you'd explain it to a non-technical person.

---

## Phase 1 — Foundation & Setup
*Goal: a clean, professional, version-controlled project skeleton that's live on GitHub.*

### 1.1 Define the scope and business question
**Do:** Write down, in one page, the problem, the business question, who cares, and what data you'll use. (This is your `project_scope.md`.) Add four short lines while you're at it: a **success metric** (how you'll know the analysis was useful), your **key assumptions**, what's **out of scope**, and the main **risk** (e.g. "production data is synthetic").
**Why it matters:** A project without a clear question becomes "I made some charts." A sharp question — *"How can a bakery cut waste without losing sales?"* — gives every later decision a purpose. The four extra lines are how professionals frame work (it's the spirit of frameworks like CRISP-DM) — and they directly answer interview questions like *"what assumptions did you make?"* and *"what are the limitations?"* without ballooning the project.
**You'll have after:** A `docs/project_scope.md` that anyone can read in two minutes and understand what you're doing, why, and what you deliberately left out.
**Say it simply:** "First I defined the real-world problem, how I'd measure success, and what I was *not* trying to solve — so the analysis stayed focused and honest about its limits."

### 1.2 Build the folder structure
**Do:** Create folders that separate raw data, cleaned data, notebooks, SQL, dashboard, and docs.
**Why it matters:** Organization signals professionalism. A reviewer who opens a tidy repo trusts the work inside it. It also stops *you* from losing track as the project grows.
**You'll have after:** A clean folder tree where every type of file has an obvious home.
**Say it simply:** "I set up the project like a filing cabinet — raw data here, finished analysis there — so it stays understandable as it grows."

### 1.3 Create a virtual environment
**Do:** Make a `.venv` and install your libraries (pandas, etc.) inside it.
**Why it matters:** It keeps this project's tools separate from everything else on your computer, so versions never clash. It also makes the project reproducible — someone else can recreate your exact setup from `requirements.txt`.
**You'll have after:** An isolated Python environment and a `requirements.txt` listing what's needed.
**Say it simply:** "I gave the project its own toolbox so it always runs the same way, on my machine or anyone else's."

### 1.4 Write the foundation files
**Do:** Create the `README.md` (the front page), `requirements.txt` (the tool list), and `.gitignore` (the "don't track this" list).
**Why it matters:** The README is the single most-read file in any repo — it's what a recruiter sees first. `.gitignore` keeps junk (caches, secrets) out of your history.
**You'll have after:** A repo that explains itself and stays clean.
**Say it simply:** "I wrote a front page so anyone landing on the project instantly gets what it is and how to run it."

### 1.5 Initialize Git and push to GitHub
**Do:** `git init`, commit, create the GitHub repo, push.
**Why it matters:** Git saves a history of every change (your safety net), and GitHub makes the project public and linkable on your CV and LinkedIn. This is the moment the project becomes *shareable*.
**You'll have after:** A live, public repository with your foundation in it.
**Say it simply:** "I put it on GitHub so I have a full history of my work and a link I can share with employers."

---

## Phase 2 — Data Understanding & Cleaning (real data)
*Goal: turn the raw, messy sales file into trustworthy, analysis-ready data.*

### 2.1 Load and explore the raw data
**Do:** Open the CSV in a notebook (`01_data_understanding.ipynb`). Look at the first rows, the column names, the data types, and the size.
**Why it matters:** You can't analyze what you don't understand. This is where you discover the data's quirks — e.g. the price is stored as text like `"0,90 €"`, dates and times are in separate columns, some quantities are negative.
**You'll have after:** A clear picture of what columns exist, how many rows, and what's wrong with the data.
**Say it simply:** "I opened the data and got to know it — what it contains, and what problems I'd have to fix."

### 2.2 Assess data quality
**Do:** Count missing values, duplicates, negative quantities, and odd product names. Write down what you find.
**Why it matters:** Bad data produces confident-but-wrong conclusions. Documenting the issues *before* fixing them shows you analyze deliberately, not by guesswork — and it's exactly the kind of detail interviewers probe.
**You'll have after:** A short list of every data problem and your plan to handle each.
**Say it simply:** "I checked the data's health — missing entries, duplicates, weird values — so I'd know exactly what to clean and why."

### 2.3 Clean the data
**Do:** In `02_data_cleaning.ipynb`: convert the price text (`"0,90 €"`) into a real number, combine date + time into one timestamp, remove or flag returns (negative quantities), drop junk product names, and create a `revenue = quantity × unit_price` column.
**Why it matters:** This is the unglamorous core of real analyst work. Each fix is a decision you can defend: *"I removed negative quantities because they're returns, not sales."* That defensibility is what credibility is made of.
**You'll have after:** A clean dataset and a documented record of every cleaning decision.
**Say it simply:** "I fixed the data so a computer could actually work with it — turning text prices into numbers, merging dates, and removing returns — and I wrote down every decision."

### 2.4 Save the cleaned dataset
**Do:** Export the cleaned data to `data/cleaned/`. Confirm your final row and product counts.
**Why it matters:** You never overwrite the raw file (it's your source of truth). Saving a clean version means later steps start from solid ground, and you finally get your *real* numbers — the ones that replace the placeholders in your README.
**You'll have after:** A reliable cleaned file and confirmed figures (e.g. "X valid sales rows across Y products").
**Say it simply:** "I saved a clean copy separately, so the original stays untouched and everything downstream is built on trustworthy data."

### 2.5 Write a data dictionary
**Do:** Create `docs/data_dictionary.md` — a simple table listing each column in your cleaned data: its name, what it means in plain business terms, its data type, and an example value.
**Why it matters:** It's the difference between "here's a file" and "here's a documented dataset anyone can pick up and understand." It's standard in professional projects, takes 20 minutes, and directly answers the interview question *"what does each field mean?"*
**You'll have after:** A one-page reference that makes your dataset self-explanatory.
**Say it simply:** "I wrote a short guide explaining every column, so anyone using the data knows exactly what it means without asking me."

---

## Phase 3 — Exploratory Data Analysis (EDA)
*Goal: answer your demand questions and find the real story in the numbers.*

### 3.1 Run descriptive statistics
**Do:** In `03_exploratory_analysis.ipynb`, calculate totals and averages: total revenue, total units, best-selling products, busiest days.
**Why it matters:** This is your first contact with the *answers*. It orients you before you go deep, and surfaces anything surprising worth chasing.
**You'll have after:** A high-level numeric summary of the business.
**Say it simply:** "I got the big-picture numbers first — total sales, top products, busy days — to see the shape of the business."

### 3.2 Test your hypotheses
**Do:** Check each hypothesis against the data: Do a few products drive most demand (Pareto / 80-20)? Do top-*selling* products differ from top-*earning* ones? Are some days far busier? Is there a seasonal pattern?
**Why it matters:** Hypotheses turn random charting into a focused investigation. The valuable ones are those that *could be wrong* — e.g. "the best-selling product also earns the most" might turn out false, and that surprise is exactly what makes you memorable.
**You'll have after:** A clear verdict — supported or not — for each hypothesis, backed by numbers.
**Say it simply:** "I had hunches about demand, and I tested each one against the data instead of assuming — some confirmed, some surprised me."

### 3.3 Validate your findings
**Do:** Before trusting a result, challenge it. Are the outliers real spikes or data errors? Is that sales jump a holiday, a promotion, or a glitch? Are any months missing observations? Could anything bias the picture?
**Why it matters:** This is the single biggest credibility step in the whole project. Anyone can produce a chart; an analyst asks whether the chart is *telling the truth*. Catching a "spike" that's really a holiday — before a manager does — is exactly the judgment interviewers are probing for.
**You'll have after:** Confidence that your findings are genuine, plus a noted list of caveats and explanations.
**Say it simply:** "I pressure-tested my own results — checking whether surprises were real patterns or just holidays, errors, or gaps — so I could stand behind every conclusion."

### 3.4 Create analytical visualizations
**Do:** Build the charts that prove your findings: a Pareto chart, a volume-vs-revenue comparison, a day-of-week bar chart, a monthly trend line.
**Why it matters:** A good chart makes a finding obvious in one glance. These visuals become the backbone of your dashboard and your README.
**You'll have after:** A set of clear charts saved in `images/charts/`.
**Say it simply:** "I turned each finding into a chart, because a picture explains a pattern faster than a paragraph."

### 3.5 Capture your findings
**Do:** Write your key takeaways in plain sentences (these feed the executive summary later).
**Why it matters:** Insights forgotten are insights wasted. Writing them now means the story is ready when you build docs and dashboard.
**You'll have after:** A short list of concrete, quantified findings.
**Say it simply:** "I wrote down what I learned in plain English, so the conclusions were ready to share."

---

## Phase 4 — SQL Modeling & KPIs
*Goal: show you can structure data and calculate business metrics in SQL, not just Python.*

### 4.1 Load the data into BigQuery
**Do:** Upload your cleaned data into Google BigQuery (a cloud database).
**Why it matters:** Most companies store data in databases, not CSVs. Doing real SQL on a cloud warehouse proves you can work the way actual teams do.
**You'll have after:** Your data living in a queryable database.
**Say it simply:** "I moved the data into a real database, because that's where companies actually keep their data."

### 4.2 Create tables and cleaning views
**Do:** Write SQL that defines your tables and a clean, standardized "view" of the data.
**Why it matters:** Views give everyone one trusted, consistent version of the data to build on — no one reinvents the cleaning.
**You'll have after:** SQL files that anyone can run to rebuild your data layer.
**Say it simply:** "I set up the database so there's one clean, agreed version of the data for everything else to use."

### 4.3 Build KPI views
**Do:** Write SQL that calculates the key metrics — revenue, units sold, top products, demand by day and month.
**Why it matters:** KPIs are the numbers a manager actually watches. Defining them in SQL means your dashboard pulls live, consistent figures.
**You'll have after:** Ready-made metric queries that feed straight into the dashboard.
**Say it simply:** "I built the exact business numbers a manager would care about, so the dashboard just plugs into them."

### 4.4 Validate the numbers
**Do:** Cross-check that your SQL totals match your Python results.
**Why it matters:** If two methods disagree, one is wrong — and catching that *before* a manager does is the whole job. Matching numbers means you can trust the dashboard.
**You'll have after:** Confidence that every figure is correct and consistent.
**Say it simply:** "I double-checked the database numbers against my earlier analysis to make sure everything agreed."

---

## Phase 5 — Dashboard
*Goal: a clean, interactive dashboard that tells the demand story at a glance.*

### 5.1 Connect the data to Data Studio
**Do:** Link BigQuery to Data Studio (free Google dashboard tool).
**Why it matters:** A dashboard is how non-analysts consume your work. Decision-makers won't read your notebook — they'll look at the dashboard.
**You'll have after:** A live data connection ready to visualize.
**Say it simply:** "I connected the data to a dashboard tool so non-technical people could explore the results themselves."

### 5.2 Build the executive overview page
**Do:** Create a top page with the headline numbers (KPI cards) — total revenue, units, top products, key trend.
**Why it matters:** Busy people want the summary in five seconds. This page delivers it.
**You'll have after:** A one-glance summary page.
**Say it simply:** "I made a front page with the most important numbers, so a manager gets the gist in seconds."

### 5.3 Build the demand / product pages
**Do:** Add pages for product ranking (Pareto), demand over time, and weekly/seasonal patterns.
**Why it matters:** This is where someone can actually *explore* — drilling into which products and which days matter.
**You'll have after:** Interactive pages that answer the real business questions.
**Say it simply:** "I added pages where you can dig into which products and which days drive the business."

### 5.4 Add filters and polish
**Do:** Add date and product filters; make the layout clean and consistent.
**Why it matters:** Filters let a viewer answer their *own* questions. Polish is the difference between "student project" and "professional tool."
**You'll have after:** A usable, good-looking dashboard.
**Say it simply:** "I added filters so people can slice the data their own way, and made it look clean and trustworthy."

### 5.5 Publish and screenshot
**Do:** Make the dashboard shareable, grab screenshots into `dashboard/screenshots/`.
**Why it matters:** A live link proves it's real; screenshots show up directly in your README for people who won't click.
**You'll have after:** A public dashboard link and images for your repo.
**Say it simply:** "I published it and saved screenshots, so it's both clickable and visible right in the project."

---

## Phase 6 — Insights, Documentation & Going Live
*Goal: tie it together into a finished, polished, shareable portfolio piece.*

### 6.1 Write the executive summary
**Do:** Write a one-page `executive_summary.md`: the question, what you found, what it means.
**Why it matters:** It's the analyst's deliverable — proof you can translate data into a clear business message. Many reviewers read *only* this.
**You'll have after:** A crisp summary a manager could act on.
**Say it simply:** "I wrote a one-pager that says what I asked, what I found, and what it means for the business."

### 6.2 Write business recommendations
**Do:** Turn findings into actions: *"Because the top 20% of products drive 80% of demand, prioritize their availability and scale back low-sellers near closing."*
**Why it matters:** Insight without a recommendation is trivia. Recommendations show you think like the business, not just the spreadsheet.
**You'll have after:** Concrete, defensible recommendations tied to your data.
**Say it simply:** "I turned the findings into specific advice a bakery could actually use to cut waste."

### 6.3 Finalize the README
**Do:** Replace the placeholders with real numbers, add the dashboard link and screenshots, list the key findings.
**Why it matters:** This is the project's storefront. A complete, results-filled README is what converts a curious recruiter into an interested one.
**You'll have after:** A polished front page that sells the work on its own.
**Say it simply:** "I finished the front page with the real results and dashboard, so it stands on its own."

### 6.4 Final commit and push
**Do:** Commit everything and push to GitHub.
**Why it matters:** Until it's pushed, the world sees an unfinished project. This makes the finished version live.
**You'll have after:** A complete, public repository.
**Say it simply:** "I pushed the finished version so the live project reflects the completed work."

### 6.5 Share on LinkedIn and add to your CV
**Do:** Write a short LinkedIn post (the story + a headline finding + the link); add the project to your CV.
**Why it matters:** A portfolio piece nobody sees does nothing for your job search. This is the step that converts effort into opportunities.
**You'll have after:** Visibility — and a concrete project to point to in applications and interviews.
**Say it simply:** "I shared it publicly, because a project only helps your career once people can see it."

---

## Phase 7 (v2) — The Synthetic Production Layer *(later extension)*
*Goal: demonstrate you can model and analyze production/waste/quality data — honestly framed as a simulation.*

**Do:** Generate a synthetic Manufacturing Execution System (MES) dataset (production batches, waste, quality inspections, machine logs), model it in SQL, and build the production/waste/quality/OEE dashboard pages.
**Why it matters:** Real production data isn't public, so simulating it lets you show the *full* plant-analytics workflow — pipeline, KPIs like yield and machine downtime, root-cause views. The key is honesty: this layer demonstrates how you'd *build* the analysis, not insights you "discovered."
**You'll have after:** An extended dashboard and a clearly-labeled engineering demonstration.
**Say it simply:** "Since real factory data isn't available, I built a realistic simulation to show exactly how I'd analyze production and waste in an actual plant — and I'm upfront that it's a demonstration, not real findings."

---

## The 30-second pitch (memorize this)

> "I'm a baker moving into data analytics, so I built a project on something I know firsthand: bakery waste. I took two years of real sales data, cleaned it, and analyzed demand patterns — which products and which days actually drive the business — using Python, SQL, and a Data Studio dashboard. The goal was to help plan production on evidence instead of guesswork, so a bakery makes less waste without losing sales. I also built a simulated production system to show how I'd extend it into a real plant's machine and waste data."

If you can say that comfortably, and explain any single step above when asked, you don't just *have* a portfolio project — you can *own* it in an interview.
