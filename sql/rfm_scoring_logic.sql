-- ========================================
-- RFM Customer Segmentation - Data Refresh
-- Precalculates RFM metrics for Power BI performance optimization
-- Run frequency: Weekly (automated via Microsoft Fabric notebook)
-- ========================================

USE [BI_Sandbox];
GO

DECLARE @LoadStart DATETIME = GETDATE();
DECLARE @Today DATE = CAST(GETDATE() AS DATE);
DECLARE @L12M_Start DATE = DATEADD(MONTH, -12, @Today);

PRINT '=========================================';
PRINT 'Starting RFM data refresh at ' + CONVERT(VARCHAR, @LoadStart, 120);
PRINT 'Analysis period: ' + CONVERT(VARCHAR, @L12M_Start, 120) + ' to ' + CONVERT(VARCHAR, @Today, 120);
PRINT '=========================================';

-- Step 1: Clear existing data
PRINT 'Truncating existing data...';
TRUNCATE TABLE [dbo].[Customers_RFM];
PRINT 'Existing data cleared.';

-- Step 2: Identify qualifying customers (at least one €20+ transaction in L12M)
PRINT 'Calculating RFM metrics...';
WITH QualifyingCustomers AS (
    SELECT DISTINCT 
        CUSTOMER_ID
    FROM (
        SELECT 
            s.CUSTOMER_ID,
            s.TRANSACTION_ID,
            SUM(s.NET_AMOUNT) as NetTransactionAmount
        FROM 
            DW.FACT.Sales s
        JOIN 
            DW.DIM.Date d ON d.DATE_KEY = s.TRANSACTION_DATE_KEY
        WHERE 
            s.CUSTOMER_ID > 0
            AND d.DATE_VALUE >= @L12M_Start
            AND d.DATE_VALUE <= @Today
        GROUP BY 
            s.CUSTOMER_ID, 
            s.TRANSACTION_ID
        HAVING 
            SUM(s.NET_AMOUNT) >= 20
    ) AS TransactionCheck
)

-- Step 3: Insert fresh RFM metrics
INSERT INTO [dbo].[Customers_RFM] (
    CUSTOMER_ID,
    CUSTOMER_CODE,
    CUSTOMER_NAME,
    EMAIL,
    EMAIL_OPTOUT,
    PHONE,
    PHONE_OPTOUT,
    LANGUAGE,
    ZIP_CODE,
    CITY,
    PREFERRED_STORE,
    LAST_PURCHASE_DATE_KEY,
    LAST_PURCHASE_DATE,
    DAYS_SINCE_PURCHASE,
    DAYS_SINCE_CATEGORY_A,
    DAYS_SINCE_CATEGORY_B,
    DAYS_SINCE_CATEGORY_C,
    TOTAL_REVENUE,
    PURCHASE_FREQUENCY,
    REVENUE_CATEGORY_A,
    FREQUENCY_CATEGORY_A,
    REVENUE_CATEGORY_B,
    FREQUENCY_CATEGORY_B,
    REVENUE_CATEGORY_C,
    FREQUENCY_CATEGORY_C,
    LOAD_DATETIME,
    DATA_PERIOD_START,
    DATA_PERIOD_END
)
SELECT 
    s.CUSTOMER_ID, 
    s.CUSTOMER_CODE,
    
    -- Customer details
    c.CUSTOMER_NAME,
    c.EMAIL,
    c.EMAIL_OPTOUT,
    c.PHONE,
    c.PHONE_OPTOUT,
    c.LANGUAGE,
    c.ZIP_CODE,
    c.CITY,
    st.STORE_NAME AS PREFERRED_STORE,
    
    -- Recency metrics
    MAX(s.TRANSACTION_DATE_KEY) AS LAST_PURCHASE_DATE_KEY,
    MAX(d.DATE_VALUE) AS LAST_PURCHASE_DATE,
    
    DATEDIFF(DAY, MAX(d.DATE_VALUE), @Today) AS DAYS_SINCE_PURCHASE,
    DATEDIFF(DAY, MAX(CASE 
                        WHEN p.CATEGORY_CODE IN ('A1', 'A2', 'A3') 
                        THEN d.DATE_VALUE 
                        ELSE NULL 
                      END), @Today) AS DAYS_SINCE_CATEGORY_A,
    DATEDIFF(DAY, MAX(CASE 
                        WHEN p.CATEGORY_CODE = 'B' 
                        THEN d.DATE_VALUE 
                        ELSE NULL 
                      END), @Today) AS DAYS_SINCE_CATEGORY_B,
    DATEDIFF(DAY, MAX(CASE 
                        WHEN p.CATEGORY_CODE = 'C' 
                        THEN d.DATE_VALUE 
                        ELSE NULL 
                      END), @Today) AS DAYS_SINCE_CATEGORY_C,
    
    -- Monetary metrics
    SUM(s.NET_AMOUNT) AS TOTAL_REVENUE,
    
    -- Frequency metrics
    COUNT(DISTINCT s.TRANSACTION_ID) AS PURCHASE_FREQUENCY,
    
    -- Category-specific metrics
    SUM(CASE 
            WHEN p.CATEGORY_CODE IN ('A1', 'A2', 'A3') 
            THEN s.NET_AMOUNT 
            ELSE 0 
        END) AS REVENUE_CATEGORY_A,
    COUNT(DISTINCT CASE 
                        WHEN p.CATEGORY_CODE IN ('A1', 'A2', 'A3') 
                        THEN s.TRANSACTION_ID 
                        ELSE NULL 
                    END) AS FREQUENCY_CATEGORY_A,
    SUM(CASE 
            WHEN p.CATEGORY_CODE = 'B' 
            THEN s.NET_AMOUNT 
            ELSE 0 
        END) AS REVENUE_CATEGORY_B,
    COUNT(DISTINCT CASE 
                        WHEN p.CATEGORY_CODE = 'B' 
                        THEN s.TRANSACTION_ID 
                        ELSE NULL 
                    END) AS FREQUENCY_CATEGORY_B,
    SUM(CASE 
            WHEN p.CATEGORY_CODE = 'C' 
            THEN s.NET_AMOUNT 
            ELSE 0 
        END) AS REVENUE_CATEGORY_C,
    COUNT(DISTINCT CASE 
                        WHEN p.CATEGORY_CODE = 'C' 
                        THEN s.TRANSACTION_ID 
                        ELSE NULL 
                    END) AS FREQUENCY_CATEGORY_C,
    
    -- Metadata for audit trail
    @LoadStart AS LOAD_DATETIME,
    @L12M_Start AS DATA_PERIOD_START,
    @Today AS DATA_PERIOD_END
FROM 
    DW.FACT.Sales s
    INNER JOIN DW.DIM.Customer c 
        ON s.CUSTOMER_ID = c.CUSTOMER_ID
    LEFT JOIN DW.DIM.Store st 
        ON CAST(c.PREFERRED_STORE_ID AS VARCHAR(50)) = CAST(st.STORE_ID AS VARCHAR(50))
    JOIN DW.DIM.Product p 
        ON s.PRODUCT_ID = p.PRODUCT_ID
    JOIN DW.DIM.Date d 
        ON d.DATE_KEY = s.TRANSACTION_DATE_KEY
WHERE 
    s.CUSTOMER_ID IN (SELECT CUSTOMER_ID FROM QualifyingCustomers)
    AND d.DATE_VALUE >= @L12M_Start
    AND d.DATE_VALUE <= @Today
    AND s.QUANTITY > 0
    AND s.DATA_SOURCE_ID <> 'EXCLUDE'
GROUP BY 
    s.CUSTOMER_ID, 
    s.CUSTOMER_CODE,
    c.CUSTOMER_NAME,
    c.EMAIL,
    c.EMAIL_OPTOUT,
    c.PHONE,
    c.PHONE_OPTOUT,
    c.LANGUAGE,
    c.ZIP_CODE,
    c.CITY,
    st.STORE_NAME;

DECLARE @LoadEnd DATETIME = GETDATE();
DECLARE @RowCount INT = @@ROWCOUNT;
DECLARE @Duration INT = DATEDIFF(SECOND, @LoadStart, @LoadEnd);

PRINT '=========================================';
PRINT 'RFM data refresh completed successfully!';
PRINT 'Customers loaded: ' + CAST(@RowCount AS VARCHAR);
PRINT 'Duration: ' + CAST(@Duration AS VARCHAR) + ' seconds (' + CAST(@Duration/60 AS VARCHAR) + ' minutes)';
PRINT 'Completed at: ' + CONVERT(VARCHAR, @LoadEnd, 120);
PRINT '=========================================';

-- Verification query
SELECT 
    COUNT(*) AS TotalCustomers,
    MAX(LOAD_DATETIME) AS LastRefreshDate,
    MIN(DATA_PERIOD_START) AS AnalysisPeriodStart,
    MAX(DATA_PERIOD_END) AS AnalysisPeriodEnd,
    SUM(TOTAL_REVENUE) AS TotalRevenue,
    AVG(PURCHASE_FREQUENCY) AS AvgFrequency,
    MAX(TOTAL_REVENUE) AS HighestCustomerValue,
    MIN(DAYS_SINCE_PURCHASE) AS MostRecentPurchaseDays
FROM [dbo].[Customers_RFM];
GO
