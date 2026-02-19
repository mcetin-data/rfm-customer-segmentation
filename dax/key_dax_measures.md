# Key DAX Calculations - RFM Customer Segmentation

## Overview

This document outlines the core DAX measures and calculated columns used in the RFM Customer Analytics dashboard. These calculations enable dynamic customer segmentation, percentile-based scoring, and customer lifecycle classification.

---

## 1. RFM Score - Recency (Calculated Column)

**Purpose:** Assigns a score (0-3) to each customer based on how recently they purchased, using percentile-based thresholds.

**Logic:** Lower days since purchase = higher score (3 = most recent, 0 = longest ago)

```dax
RFM_Recency_Score = 
VAR DaysSince = Customers_RFM[DAYS_SINCE_PURCHASE]
VAR Percentile_33 = PERCENTILE.INC(Customers_RFM[DAYS_SINCE_PURCHASE], 0.33)
VAR Percentile_67 = PERCENTILE.INC(Customers_RFM[DAYS_SINCE_PURCHASE], 0.67)

RETURN
    SWITCH(
        TRUE(),
        ISBLANK(DaysSince), BLANK(),
        DaysSince <= Percentile_33, 3,      -- Top 33%: Most recent
        DaysSince <= Percentile_67, 2,      -- Middle 33%: Moderate
        1                                    -- Bottom 33%: Least recent
    )
```

**Key Design Decision:** 
- Uses `PERCENTILE.INC` to create dynamic thresholds that adjust as customer behavior changes
- Tertile distribution (33/33/33) rather than quintiles - simpler for business users to interpret
- Inverted scoring: lower days = higher score (aligns with "more recent = better")

---

## 2. RFM Score - Monetary (Calculated Column)

**Purpose:** Assigns a score (0-3) to each customer based on total revenue contribution, using custom percentile distribution.

**Logic:** Higher revenue = higher score, with top 20% customers getting highest score

```dax
RFM_Monetary_Score = 
VAR Revenue = Customers_RFM[TOTAL_REVENUE]
VAR Percentile_20 = PERCENTILE.INC(Customers_RFM[TOTAL_REVENUE], 0.20)
VAR Percentile_60 = PERCENTILE.INC(Customers_RFM[TOTAL_REVENUE], 0.60)

RETURN
    SWITCH(
        TRUE(),
        ISBLANK(Revenue), BLANK(),
        Revenue >= Percentile_60, 3,        -- Top 40%: High value
        Revenue >= Percentile_20, 2,        -- Middle 40%: Moderate value  
        1                                    -- Bottom 20%: Low value
    )
```

**Key Design Decision:**
- Non-uniform distribution (20/40/40) requested by Marketing team
- Identifies top 20% of customers by revenue for VIP treatment
- Avoids over-segmentation of low-value customers

---

## 3. RFM Score - Frequency (Calculated Column)

**Purpose:** Assigns a score (0-3) based on purchase frequency (number of transactions).

**Logic:** More frequent purchases = higher score

```dax
RFM_Frequency_Score = 
VAR Frequency = Customers_RFM[PURCHASE_FREQUENCY]
VAR Percentile_33 = PERCENTILE.INC(Customers_RFM[PURCHASE_FREQUENCY], 0.33)
VAR Percentile_67 = PERCENTILE.INC(Customers_RFM[PURCHASE_FREQUENCY], 0.67)

RETURN
    SWITCH(
        TRUE(),
        ISBLANK(Frequency), BLANK(),
        Frequency >= Percentile_67, 3,      -- Top 33%: Most frequent
        Frequency >= Percentile_33, 2,      -- Middle 33%: Moderate
        1                                    -- Bottom 33%: Least frequent
    )
```

---

## 4. RFM Combined Score (Calculated Column)

**Purpose:** Creates a 3-digit composite score combining Recency, Frequency, and Monetary scores.

**Format:** First digit = Recency, Second digit = Frequency, Third digit = Monetary

```dax
RFM_Score = 
VAR R = Customers_RFM[RFM_Recency_Score]
VAR F = Customers_RFM[RFM_Frequency_Score]
VAR M = Customers_RFM[RFM_Monetary_Score]

RETURN
    IF(
        ISBLANK(R) || ISBLANK(F) || ISBLANK(M),
        BLANK(),
        FORMAT(R, "0") & FORMAT(F, "0") & FORMAT(M, "0")
    )
```

**Example scores:**
- `333` = Best customers (recent, frequent, high-value)
- `111` = At-risk customers (dormant, infrequent, low-value)
- `313` = High-value but infrequent (VIP occasional buyers)

---

## 5. Customer Lifecycle Cohort (Calculated Column)

**Purpose:** Classifies customers into lifecycle stages based on activity patterns across multiple time periods.

**Cohorts:**
- **New Customer:** First purchase in last 12 months
- **Reactivated:** Active 2-3 years ago, dormant 1-2 years ago, active again now
- **Lost:** Active 2-3 years ago, no purchases in last 2 years
- **Existing:** Active now, doesn't fit other special categories

```dax
Customer_Cohort = 
VAR CustomerID = Customers_RFM[CUSTOMER_ID]
VAR Today = TODAY()
VAR L12M_Start = EDATE(Today, -12) + 1
VAR P12M_Start = EDATE(Today, -24) + 1
VAR P24M_Start = EDATE(Today, -36) + 1

-- Check if customer is new (first purchase in L12M)
VAR IsNew = 
    CALCULATE(
        COUNTROWS(DimCustomer),
        ALL(Customers_RFM),
        DimCustomer[CUSTOMER_ID] = CustomerID,
        DimCustomer[IS_VALID_NEW_CUSTOMER] = TRUE(),
        DimCustomer[FIRST_PURCHASE_DATE] >= L12M_Start,
        DimCustomer[FIRST_PURCHASE_DATE] <= Today
    ) > 0

-- Check activity in three rolling 12-month periods
VAR ActiveL12M = 
    CALCULATE(
        COUNTROWS(CustomerActivityHistory),
        ALL(Customers_RFM),
        CustomerActivityHistory[CUSTOMER_ID] = CustomerID,
        CustomerActivityHistory[ACTIVITY_DATE] >= L12M_Start,
        CustomerActivityHistory[ACTIVITY_DATE] <= Today
    ) > 0

VAR ActiveP12M = 
    CALCULATE(
        COUNTROWS(CustomerActivityHistory),
        ALL(Customers_RFM),
        CustomerActivityHistory[CUSTOMER_ID] = CustomerID,
        CustomerActivityHistory[ACTIVITY_DATE] >= P12M_Start,
        CustomerActivityHistory[ACTIVITY_DATE] < L12M_Start
    ) > 0

VAR ActiveP24M = 
    CALCULATE(
        COUNTROWS(CustomerActivityHistory),
        ALL(Customers_RFM),
        CustomerActivityHistory[CUSTOMER_ID] = CustomerID,
        CustomerActivityHistory[ACTIVITY_DATE] >= P24M_Start,
        CustomerActivityHistory[ACTIVITY_DATE] < P12M_Start
    ) > 0

-- Define complex cohort patterns
VAR IsReactivated = ActiveL12M && ActiveP24M && NOT(ActiveP12M)
VAR IsLost = ActiveP24M && NOT(ActiveP12M) && NOT(ActiveL12M)
VAR IsExisting = ActiveL12M && NOT(IsNew) && NOT(IsReactivated)

RETURN
    SWITCH(
        TRUE(),
        IsNew, "New Customer",
        IsReactivated, "Reactivated",
        IsLost, "Lost Customer",
        IsExisting, "Existing Customer",
        BLANK()
    )
```

**Key Design Patterns:**
- `ALL(Customers_RFM)` prevents circular dependency in calculated column
- Three distinct 12-month windows (L12M, P12M, P24M) enable pattern detection
- Priority-based classification using `SWITCH(TRUE())` pattern
- Activity history table enables efficient date-range filtering

---

## 6. RFM Segment Label (Calculated Column)

**Purpose:** Maps RFM scores to business-friendly segment names using a configuration table.

```dax
RFM_Segment = 
VAR Score = Customers_RFM[RFM_Score]

RETURN
    CALCULATE(
        VALUES(RFM_Segment_Config[Segment_Name]),
        RFM_Segment_Config[RFM_Score] = Score
    )
```

**Supporting Table:** `RFM_Segment_Config` (disconnected)
- Maps each RFM score (e.g., "333", "311") to segment names
- Allows Marketing team to adjust segment definitions without modifying DAX
- Examples: "Champions", "Loyal Customers", "At Risk", "Dormant"

---

## Performance Optimization Notes

### Why Calculated Columns vs. Measures?

**RFM scores are calculated columns because:**
1. Complex logic with multiple `CALCULATE()` operations per customer
2. Pre-calculation improves dashboard interactivity (no runtime recalculation)
3. Scores are static for a given refresh period (recalculate weekly with data refresh)
4. Used extensively as slicers and filters (column storage more efficient)

### Refresh Strategy

- RFM base table refreshed weekly via SQL stored procedure
- Calculated columns refresh automatically when base data refreshes
- Percentiles recalculate dynamically, adapting to changing customer behavior
- No manual recalculation required

---

## Technical Patterns Used

1. **Percentile-based thresholding** - Dynamic segmentation that adjusts with data
2. **Circular dependency prevention** - `ALL()` function to break filter context
3. **Multi-period analysis** - Three rolling 12-month windows for lifecycle detection
4. **Configuration table pattern** - Business users can modify segments without DAX changes
5. **Row context isolation** - `CALCULATE()` with explicit filters for reliable column calculations
