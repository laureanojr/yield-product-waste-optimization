# Yield & Production Waste Optimization in Industrial Food Manufacturing

## Project Overview

As a baker, I have seen firsthand how difficult it can be to balance production with customer demand. Producing too much creates waste, while producing too little can lead to missed sales opportunities and dissatisfied customers.

This project explores how data can be used to support better production planning in an industrial bakery environment. Using real bakery sales data, I analyze customer demand patterns, product performance, and sales trends to identify opportunities for reducing waste and improving operational efficiency.

To make the project more representative of a real manufacturing environment, I later combine the sales data with a synthetic production dataset that simulates production batches, waste records, and quality control processes.

---

## The Business Challenge

Bakery products are highly perishable and often need to be produced daily. Because of this, production planning is a constant challenge.

When production exceeds demand, products may go unsold and end up as waste. When production falls short of demand, potential revenue can be lost because products are unavailable when customers want them.

The goal is to better understand demand patterns so that production decisions can be based on data rather than assumptions.

### Business Question

How can an industrial bakery reduce production waste while still meeting customer demand and maintaining revenue?

---

## Project Goal

The goal of this project is to use historical sales data to understand demand behaviour and identify opportunities to improve production planning.

Specifically, I want to:

- Identify the products that drive the highest demand
- Compare sales volume with revenue contribution
- Understand how demand changes over time
- Build a foundation for production forecasting
- Explore ways to reduce waste and improve efficiency

---

## Stakeholders

The results of this analysis could be useful for:

- Production Managers
- Operations Managers
- Plant Managers
- Supply Chain Teams
- Business Leaders responsible for production planning

---

## Dataset

### Sales Data (real)

This project uses a real bakery sales dataset covering the period from January 2021 to September 2022.

The dataset contains:

- Transaction date
- Transaction time
- Product name
- Quantity sold
- Unit price

After cleaning, the dataset contains roughly 232,710 valid sales records across ~149 unique products. *(Exact figures verified during the data cleaning phase.)*

### Production Data (synthetic)

Because real production and waste information is not publicly available, a synthetic manufacturing dataset is created later in the project to simulate a Manufacturing Execution System (MES). It is used to demonstrate the data modeling, pipeline, and dashboard workflow — **not** to claim discovered operational findings.

The synthetic dataset includes:

- Production batches
- Waste records
- Quality inspections
- Production schedules
- Production performance metrics

Combining demand data with production data allows the project to demonstrate how the relationship between sales, production output, and waste would be analyzed in a real plant.

---

## Expected Outcome

By understanding which products drive demand and how demand changes over time, production teams can make more informed planning decisions.

The long-term objective is to help reduce waste, improve production efficiency, and support more profitable operations through data-driven decision-making.
