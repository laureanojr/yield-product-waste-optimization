# How I Built This Project

I'm a baker. I trained as a Bäckergeselle and spent about nine years in industrial food production before moving into data analytics, so this project isn't a random dataset I grabbed off Kaggle. It's the problem I lived with every day.

In a bakery you're always guessing. Make too much and it goes in the bin at closing. Make too little and you turn customers away and lose the sale. I wanted to find out whether real sales data could take some of that guesswork out of production planning.

This is my record of how I built the whole thing and why I made each call. If you're a recruiter reading it, it should show you how I think. If it's me reading it before an interview, it should remind me why I did what I did.

## Two parts, and only one of them is real

I want to be straight about this from the start because it matters.

The project has two halves. The first is built on real bakery sales data, and that's the only half I draw business conclusions from. Every finding and every number comes from real data.

The second half is a simulated production system. Real factory data on waste, machine downtime and quality control isn't publicly available, so I built a synthetic version to show how I'd analyse it if I had it. It's a demonstration of method, not a source of findings. I never dress up made-up numbers as things I discovered. If it comes up in an interview, my answer is simple: only the first part supports conclusions, the second shows how I'd work with production data.

## Phase 1 — Setting up the project

Before touching any data I built the skeleton. A folder structure that keeps raw data, cleaned data, notebooks, SQL and the dashboard in separate places. A virtual environment so this project's Python libraries stay isolated and anyone can rebuild my exact setup from `requirements.txt`. Git and a GitHub repo so I've got a full history of my work and a link I can share.

I also wrote the README first, not last. On GitHub the README is the front page, it's the first thing anyone sees, so I didn't want it sitting empty. And I wrote a one-page scope document: the problem, the business question, who'd care about the answer, plus a few lines on my assumptions and what I was deliberately leaving out. That kept me focused later and it's the honest answer to the interview question about a project's limitations.

## Phase 2 — Cleaning the sales data

The raw file had about 234,000 rows, and "no missing values" turned out to be a long way from "ready to analyse."

A few things needed sorting. There was a leftover row-number column with no meaning, so I dropped it. The prices were stored as text like `"0,90 €"`, euro sign and a comma for the decimal, which a computer can't do maths on, so I converted them to real numbers. Date and time sat in separate columns, so I merged them into one proper timestamp. That one step is what later let me pull out the day of the week, the hour and the month.

Then the two judgement calls. There were 1,295 rows with negative quantities, which are returns and refunds. This project is about demand, and a refund is the opposite of demand, so I removed them. There were also 32 rows priced at zero, most likely giveaways or till errors, and I removed those too because a zero price throws off any revenue figure. One row was both, which is why the counts don't add up to exactly 1,327. After that I added a revenue column, quantity times price.

I ended with 232,679 clean sales lines across 147 products, and I wrote a short data dictionary so anyone picking up the file knows what each column means without asking me.

One lesson from this phase that stuck with me: I ran my notebook cells out of order and got numbers that looked fine but were wrong. The final count didn't reflect a filter I'd applied afterwards. So now I always restart the kernel and run everything top to bottom before I trust a result. A notebook that only gives the right answer if you click the cells in a particular order isn't reproducible, and reproducible is the whole point.

## Phase 3 — Finding the story

This is where the data started talking.

A single product carries the business. The traditional baguette is about a third of everything sold, more than the next four products put together. So the first hypothesis, that a few products drive most of the demand, wasn't just true, it was extreme.

Best sellers aren't best earners. The baguette leads on both, but underneath that the two lists split apart. Sandwiches sell in far smaller numbers yet jump near the top on revenue because they carry a much higher price than a ninety-cent baguette. If you planned production off unit counts alone, you'd quietly undervalue your best money-makers.

Demand is weekend-heavy. Sunday is the biggest day by a wide margin. Wednesday looked like the deadest day, and this is where I nearly got it wrong. Before writing that down I checked how many of each weekday were actually in the data, and Wednesday showed up far fewer times than the rest. The bakery is closed most Wednesdays. So the real finding isn't "nobody buys bread on Wednesday," it's "the shop isn't open." Catching that difference before it went into a report is the kind of check I now do by habit.

There's also a clear summer peak. July and August are the strongest months in both years, and it holds up even when I compare average revenue per open day rather than raw totals, so it's a real seasonal pattern and not just a side effect of some months having more trading days. And it's a morning business, sales pile up between eight and noon and drop off a cliff in the afternoon.

I turned the main findings into charts and saved them as images so they'd show up in the README and the dashboard.

## Phase 4 — SQL and BigQuery (next)

The analysis so far lives in Python, but most companies keep their data in a database and query it with SQL, so next I'll load the cleaned data into BigQuery and rebuild the key numbers there. Tables, a clean view of the data, and views for the business metrics like revenue, top products and demand by day and month. Then I'll check the SQL totals against my Python results, because if the two disagree, one of them is wrong and I'd rather find that myself.

I'm including this partly because SQL is the skill most junior analyst jobs actually ask for, more than Python in a lot of cases.

## Phase 5 — The dashboard

Numbers in a notebook are for me. A dashboard is for everyone else. I'll connect the data to Google's Data Studio (the free tool, recently renamed back from Looker Studio) and build a few pages: an overview with the headline figures, a product page with the rankings, and a page for the day-of-week and seasonal patterns. Filters so someone can slice it their own way, then I'll publish it and take screenshots for the repo.

## Phase 6 — Writing it up and going live

Last comes the part that actually gets read. A one-page summary of what I asked, what I found and what it means. Recommendations that turn the findings into something a bakery could act on, like prioritising baguette availability, protecting the higher-value sandwiches, and scaling up for weekends and summer. Then I'll finish the README with the real numbers and the dashboard link, push it all, and put it on my CV and LinkedIn. A project nobody sees doesn't help my job search.

## Phase 7 — The production simulation (later)

Once the real-data project is finished and shared, I'll add the synthetic manufacturing layer: simulated production batches, waste, quality checks and machine logs, modelled in SQL with its own dashboard pages. This is where I show I can handle production and waste analysis end to end. And I'll keep saying it plainly, it's a simulation to demonstrate the method, not a set of real findings.

## How I'd sum it up in half a minute

I'm a baker moving into data analytics, so I built a project on something I know first-hand: bakery waste. I took nearly two years of real sales data, cleaned it, and worked out what actually drives the business, which products, which days, which months, so production can be planned on evidence instead of a gut feeling. Then I built a simulated production system to show how I'd take the same approach into a real plant's waste and machine data. The point of the whole thing is less bread in the bin without turning customers away.
