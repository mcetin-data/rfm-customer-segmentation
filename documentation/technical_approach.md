# Technical Implementation Approach

## Architecture Overview

This RFM segmentation solution uses a **hybrid architecture** combining SQL-based pre-calculation with Power BI visualization to optimize performance and enable flexible analysis of 800,000+ customer records.

```
Azure SQL Database → Weekly SQL Refresh → Power BI Service → Dashboard
                           ↓
                  Microsoft Fabric Notebook
                  (Orchestration & Logging)
```

---

## Key Design Decisions

### 1. Pre-Calculated Tables Strategy

**Challenge:** Direct querying of 5M+ transaction rows in Power BI caused slow dashboards and refresh timeouts.

**Solution:** Pre-aggregate RFM metrics in SQL, refresh weekly.

**Benefits:**
- 60%+ reduction in dashboard load times
- Power BI Service refresh completes in <5 minutes (vs 30+ min previously)
- Only sales fact table refreshes daily; RFM table refreshes weekly
- Enables complex SQL logic (percentiles, CTEs) not easily replicated in DAX

**Trade-off:** Data is up to 7 days stale, but acceptable for strategic marketing analysis.

---

### 2. €20 Minimum Transaction Threshold

**Business Rule:** Customers must have at least ONE transaction totaling €20+ in last 12 months to be included in RFM analysis.

**Rationale:**
- Excludes micro-transactions (promotional items, gift bags)
- Excludes return-only customers (no real purchase intent)
- Focuses analysis on customers with meaningful purchase behavior
- Requested by Marketing team after initial analysis showed noise from low-value transactions

**Implementation:**
```sql
WITH QualifyingCustomers AS (
    SELECT DISTINCT CUSTOMER_ID
    FROM (
        SELECT CUSTOMER_ID, TRANSACTION_ID, SUM(NET_AMOUNT) as Total
        FROM Sales
        WHERE DATE >= L12M_Start
        GROUP BY CUSTOMER_ID, TRANSACTION_ID
        HAVING SUM(NET_AMOUNT) >= 20
    )
)
```

Reduces dataset from ~1.2M customers to ~800K qualified customers.

---

### 3. Percentile-Based RFM Scoring

**Traditional approach:** Fixed thresholds (e.g., Recency < 30 days = score 5)

**Our approach:** Dynamic percentile-based thresholds using `PERCENTILE.INC()`

**Why percentiles:**
- Adapts automatically as customer behavior changes
- Seasonal variations don't break segmentation logic
- Thresholds self-adjust for business growth/contraction
- Consistent segment sizes (e.g., top 20% always gets score 3)

**Custom distribution for Monetary:**
- Recency/Frequency: Tertile split (33% / 33% / 33%)
- Monetary: Custom split (20% / 40% / 40%)
- Top 20% of customers by revenue flagged as high-value (Marketing requirement)

---

### 4. Category-Specific Metrics

**Beyond total RFM:** Calculate Recency, Frequency, and Monetary for each product category independently.

**Example categories:**
- Category A (Children's products)
- Category B (Women's products)  
- Category C (Men's products)

**Use case:** Enables targeted campaigns like:
- "You haven't shopped Category B in 90 days - here's a special offer!"
- Cross-sell opportunities: Identify Category A buyers who never purchased Category C

**Implementation:**
```sql
DATEDIFF(DAY, 
    MAX(CASE WHEN CATEGORY_CODE = 'B' THEN DATE END), 
    @Today
) AS DAYS_SINCE_CATEGORY_B
```

Each customer gets 12 metrics: 3 overall RFM + 3 per category × 3 categories.

---

### 5. Customer Lifecycle Classification

**Beyond RFM scores:** Classify customers into lifecycle cohorts using multi-period analysis.

**Cohorts:**
- **New Customer:** First purchase in last 12 months (with €20+ validation)
- **Reactivated:** Purchased 2-3 years ago, dormant for a year, active again now
- **Lost Customer:** Purchased 2-3 years ago, no activity for 24+ months
- **Existing Customer:** Active, doesn't fit special categories

**Pattern detection logic:**
```
Period P24M (2-3 years ago): Active?
Period P12M (1-2 years ago): Active?
Period L12M (last 12 months): Active?

Pattern for "Reactivated": TRUE / FALSE / TRUE
Pattern for "Lost":         TRUE / FALSE / FALSE
```

Enables win-back campaigns for reactivation and last-chance offers for lost customers.

---

### 6. Microsoft Fabric Orchestration

**Challenge:** Weekly SQL refresh originally ran via SQL Agent job, difficult to monitor and log.

**Solution:** Migrated orchestration to Microsoft Fabric notebook.

**Fabric notebook handles:**
- Executes SQL refresh query via Azure SQL connection
- Captures execution time, row counts, errors
- Logs results for audit trail
- Triggers Power BI dataset refresh after SQL completes
- Sends email notification on success/failure

**Benefits:**
- Centralized scheduling (all data pipelines visible in Fabric workspace)
- Better error handling and retry logic
- Version-controlled orchestration code
- Integrated with Power BI workspace permissions

---

## Performance Characteristics

**Weekly SQL Refresh:**
- Duration: 5-8 minutes for 800K customers
- Data volume: Processes 5M+ transaction rows, outputs 800K customer records
- Timing: Runs Sunday 2 AM (low system load)

**Power BI Service Refresh:**
- Duration: <5 minutes (only sales table refreshes daily)
- Weekly full refresh: <10 minutes total
- Dashboard load time: <3 seconds for initial visual rendering

**Scalability:**
- Current: 800K customers, 5M transactions
- Projected capacity: Up to 2M customers without architecture changes
- Beyond 2M: Consider partitioning by region or migrating to Synapse

---

## Data Quality & Validation

**Automated checks in SQL:**
- Verify row count matches expected range (780K-820K customers)
- Check for NULL values in critical columns (customer ID, RFM scores)
- Validate date ranges (ensure L12M window is correct)
- Compare total revenue to previous refresh (flag >20% variance)

**Power BI validation:**
- Custom measure: `Data Freshness = DATEDIFF(DAY, MAX(LoadDate), TODAY())`
- Alert if data >8 days old
- Monthly review: Segment distribution consistency check

---

## Maintenance & Evolution

**Regular maintenance:**
- Weekly: Monitor refresh logs, validate data quality
- Monthly: Review percentile thresholds, adjust if business changes
- Quarterly: Analyze segment definitions with Marketing team

**Future enhancements under consideration:**
- Real-time RFM scores via streaming dataset (for web personalization)
- Predictive churn modeling using RFM + additional features
- Geographic analysis (customer clustering by location)
- Integration with marketing automation platform (direct segment sync)

---

## Lessons Learned

**What worked well:**
- Pre-calculation strategy eliminated performance bottlenecks
- Percentile-based scoring proved more robust than fixed thresholds
- Category-specific metrics unlocked targeted campaign opportunities
- Training documentation improved Marketing team adoption

**What we'd do differently:**
- Earlier involvement of Marketing in threshold definition (avoided rework)
- More comprehensive logging from day one (debugging was harder initially)
- Automated testing of edge cases (e.g., customers with only returns)

**Skills demonstrated:**
- Performance optimization through architecture design
- Stakeholder collaboration (translating business needs to technical requirements)
- End-to-end ownership (SQL → Power BI → training → ongoing support)
