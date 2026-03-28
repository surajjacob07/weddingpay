-- ============================================================
-- WeddingPay — Analytics Queries (Redshift)
-- KPIs, Funnels, Revenue, Cohort Analysis
-- ============================================================

-- -----------------------------------------------
-- 1. NORTH STAR: Daily / Weekly Platform Overview
-- -----------------------------------------------
SELECT
    DATE_TRUNC('week', gt.created_at) AS week,
    COUNT(DISTINCT gt.couple_id)                    AS active_couples,
    COUNT(DISTINCT gt.guest_id)                     AS unique_gifting_guests,
    COUNT(gt.txn_id)                                AS total_gift_txns,
    ROUND(SUM(gt.amount_paise) / 100.0, 0)          AS total_gift_pool_inr,
    ROUND(AVG(gt.amount_paise) / 100.0, 0)          AS avg_gift_size_inr,
    ROUND(SUM(gt.amount_paise) * 0.005 / 100.0, 0) AS service_fee_earned_inr,
    COUNT(CASE WHEN gt.media_type IS NOT NULL THEN 1 END) AS gifts_with_media,
    ROUND(COUNT(CASE WHEN gt.media_type IS NOT NULL THEN 1 END) * 100.0 / COUNT(gt.txn_id), 1) AS media_attach_rate_pct
FROM gift_transaction gt
WHERE gt.status = 'success'
    AND gt.created_at >= DATEADD('month', -3, CURRENT_DATE)
GROUP BY 1
ORDER BY 1 DESC;

-- -----------------------------------------------
-- 2. GUEST GIFTING FUNNEL (per couple cohort)
-- -----------------------------------------------
SELECT
    DATE_TRUNC('month', c.created_at)               AS cohort_month,
    COUNT(DISTINCT c.couple_id)                      AS couples_signed_up,
    COUNT(DISTINCT g.guest_id)                       AS total_guests_invited,
    COUNT(DISTINCT g.guest_id) FILTER (WHERE g.invitation_status = 'opened') AS invites_opened,
    COUNT(DISTINCT g.guest_id) FILTER (WHERE g.invitation_status = 'gifted') AS guests_gifted,
    ROUND(
        COUNT(DISTINCT g.guest_id) FILTER (WHERE g.invitation_status = 'gifted') * 100.0
        / NULLIF(COUNT(DISTINCT g.guest_id), 0), 1
    )                                                AS guest_gifting_rate_pct,
    ROUND(
        COUNT(DISTINCT g.guest_id) FILTER (WHERE g.invitation_status = 'opened') * 100.0
        / NULLIF(COUNT(DISTINCT g.guest_id), 0), 1
    )                                                AS invite_open_rate_pct
FROM couple c
LEFT JOIN guest g ON g.couple_id = c.couple_id
GROUP BY 1
ORDER BY 1 DESC;

-- -----------------------------------------------
-- 3. SUBSCRIPTION PLAN MIX & REVENUE
-- -----------------------------------------------
SELECT
    c.plan_tier,
    COUNT(*)                                         AS couples,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS plan_mix_pct,
    SUM(CASE c.plan_tier
        WHEN 'classic' THEN 499900
        WHEN 'premium' THEN 999900
        WHEN 'luxury'  THEN 2499900
    END) / 100.0                                     AS subscription_revenue_inr,
    ROUND(AVG(gw.total_issued_paise) / 100.0, 0)    AS avg_gift_pool_inr,
    ROUND(AVG(gw.cards_count), 1)                   AS avg_cards_per_couple
FROM couple c
LEFT JOIN gift_wallet gw ON gw.couple_id = c.couple_id
WHERE c.subscription_status = 'active'
GROUP BY c.plan_tier
ORDER BY subscription_revenue_inr DESC;

-- -----------------------------------------------
-- 4. REGISTRY CATEGORY PERFORMANCE
-- -----------------------------------------------
SELECT
    r.category,
    COUNT(DISTINCT r.registry_id)                    AS total_registries,
    ROUND(AVG(r.target_amount_paise) / 100.0, 0)    AS avg_target_inr,
    ROUND(AVG(r.contributed_amount_paise) / 100.0, 0) AS avg_contributed_inr,
    ROUND(AVG(r.contributed_amount_paise * 100.0 / NULLIF(r.target_amount_paise, 0)), 1) AS avg_fulfillment_pct,
    COUNT(DISTINCT r.registry_id) FILTER (WHERE r.is_fulfilled) AS fulfilled_count,
    COUNT(DISTINCT gt.txn_id)                        AS total_gift_txns,
    ROUND(AVG(gt.amount_paise) / 100.0, 0)          AS avg_gift_size_inr
FROM registry r
LEFT JOIN gift_transaction gt ON gt.registry_id = r.registry_id AND gt.status = 'success'
GROUP BY r.category
ORDER BY avg_contributed_inr DESC;

-- -----------------------------------------------
-- 5. VENDOR PAYMENT ADOPTION & FLOW
-- -----------------------------------------------
SELECT
    v.type                                           AS vendor_type,
    COUNT(DISTINCT vp.payment_id)                    AS total_payments,
    COUNT(DISTINCT vp.couple_id)                     AS couples_using_vendor,
    ROUND(SUM(vp.amount_paise) / 100.0, 0)          AS total_paid_inr,
    ROUND(AVG(vp.amount_paise) / 100.0, 0)          AS avg_payment_inr,
    ROUND(SUM(vp.vendor_fee_paise) / 100.0, 0)      AS fee_earned_inr,
    ROUND(
        AVG(EXTRACT(EPOCH FROM (vp.settled_at - vp.escrow_at)) / 3600), 1
    )                                                AS avg_settlement_hours,
    COUNT(CASE WHEN vp.status = 'disputed' THEN 1 END) AS disputes
FROM vendor_payment vp
JOIN vendor v ON v.vendor_id = vp.vendor_id
WHERE vp.status IN ('settled', 'disputed')
GROUP BY v.type
ORDER BY total_paid_inr DESC;

-- -----------------------------------------------
-- 6. PARTNER / AGGREGATOR PERFORMANCE
-- -----------------------------------------------
SELECT
    p.name                                           AS partner_name,
    p.type                                           AS partner_type,
    COUNT(DISTINCT c.couple_id)                      AS couples_activated,
    ROUND(SUM(CASE c.plan_tier
        WHEN 'classic' THEN 499900
        WHEN 'premium' THEN 999900
        WHEN 'luxury'  THEN 2499900
    END) / 100.0, 0)                                 AS total_subscription_rev_inr,
    ROUND(SUM(CASE c.plan_tier
        WHEN 'classic' THEN 499900
        WHEN 'premium' THEN 999900
        WHEN 'luxury'  THEN 2499900
    END) * p.revenue_share_pct / 10000.0, 0)        AS partner_payout_inr,
    ROUND(AVG(gw.total_issued_paise) / 100.0, 0)    AS avg_gift_pool_inr,
    ROUND(SUM(gw.total_issued_paise) * 0.005 / 100.0, 0) AS service_fee_inr
FROM partner p
JOIN couple c ON c.partner_id = p.partner_id
LEFT JOIN gift_wallet gw ON gw.couple_id = c.couple_id
WHERE c.subscription_status = 'active'
GROUP BY p.partner_id, p.name, p.type, p.revenue_share_pct
ORDER BY total_subscription_rev_inr DESC;

-- -----------------------------------------------
-- 7. FLOAT INCOME ESTIMATION (Gift Cards AUM)
-- -----------------------------------------------
-- Estimate outstanding float (issued but not yet redeemed)
-- Float income = outstanding_balance * 6% p.a. / 365 per day
SELECT
    CURRENT_DATE                                     AS as_of_date,
    ROUND(SUM(gw.total_issued_paise) / 100.0, 0)    AS total_issued_inr,
    ROUND(SUM(gw.total_redeemed_paise) / 100.0, 0)  AS total_redeemed_inr,
    ROUND(SUM(gw.available_balance_paise) / 100.0, 0) AS float_aum_inr,
    ROUND(SUM(gw.available_balance_paise) * 0.06 / 36500.0, 0) AS float_income_today_inr,
    ROUND(SUM(gw.available_balance_paise) * 0.06 / 12.0 / 100.0, 0) AS float_income_monthly_inr
FROM gift_wallet gw;

-- -----------------------------------------------
-- 8. COHORT RETENTION — 30/60/90 DAY GIFT VELOCITY
-- -----------------------------------------------
WITH couple_first_gift AS (
    SELECT
        couple_id,
        MIN(created_at) AS first_gift_at
    FROM gift_transaction
    WHERE status = 'success'
    GROUP BY couple_id
),
gift_velocity AS (
    SELECT
        cfg.couple_id,
        cfg.first_gift_at,
        COUNT(gt.txn_id) FILTER (
            WHERE gt.created_at BETWEEN cfg.first_gift_at AND cfg.first_gift_at + INTERVAL '30 days'
        ) AS gifts_d0_d30,
        COUNT(gt.txn_id) FILTER (
            WHERE gt.created_at BETWEEN cfg.first_gift_at + INTERVAL '30 days' AND cfg.first_gift_at + INTERVAL '60 days'
        ) AS gifts_d30_d60,
        COUNT(gt.txn_id) FILTER (
            WHERE gt.created_at BETWEEN cfg.first_gift_at + INTERVAL '60 days' AND cfg.first_gift_at + INTERVAL '90 days'
        ) AS gifts_d60_d90
    FROM couple_first_gift cfg
    JOIN gift_transaction gt ON gt.couple_id = cfg.couple_id AND gt.status = 'success'
    GROUP BY cfg.couple_id, cfg.first_gift_at
)
SELECT
    DATE_TRUNC('month', first_gift_at)              AS cohort_month,
    COUNT(couple_id)                                 AS couples,
    ROUND(AVG(gifts_d0_d30), 1)                     AS avg_gifts_month_1,
    ROUND(AVG(gifts_d30_d60), 1)                    AS avg_gifts_month_2,
    ROUND(AVG(gifts_d60_d90), 1)                    AS avg_gifts_month_3
FROM gift_velocity
GROUP BY 1
ORDER BY 1 DESC;

-- -----------------------------------------------
-- 9. REVENUE P&L SUMMARY (Monthly)
-- -----------------------------------------------
WITH monthly_txns AS (
    SELECT
        DATE_TRUNC('month', gt.created_at)           AS month,
        SUM(gt.amount_paise)                         AS gift_pool_paise,
        SUM(gt.amount_paise) * 0.005                 AS service_fee_paise,
        SUM(gt.mdr_paise)                            AS mdr_cost_paise,
        SUM(gt.pinelabs_fee_paise)                   AS pinelabs_cost_paise,
        COUNT(gt.txn_id)                             AS txn_count
    FROM gift_transaction gt
    WHERE gt.status = 'success'
    GROUP BY 1
),
monthly_subscriptions AS (
    SELECT
        DATE_TRUNC('month', c.subscription_paid_at)  AS month,
        SUM(CASE c.plan_tier
            WHEN 'classic' THEN 499900
            WHEN 'premium' THEN 999900
            WHEN 'luxury'  THEN 2499900
        END)                                         AS subscription_rev_paise,
        COUNT(*)                                     AS new_couples
    FROM couple c
    WHERE c.subscription_paid_at IS NOT NULL
    GROUP BY 1
),
monthly_vendor_fees AS (
    SELECT
        DATE_TRUNC('month', vp.settled_at)           AS month,
        SUM(vp.vendor_fee_paise)                     AS vendor_fee_paise
    FROM vendor_payment vp
    WHERE vp.status = 'settled'
    GROUP BY 1
)
SELECT
    COALESCE(mt.month, ms.month, mvf.month)          AS month,
    ROUND(COALESCE(ms.subscription_rev_paise, 0) / 100.0, 0) AS subscription_rev_inr,
    ROUND(COALESCE(mt.service_fee_paise, 0) / 100.0, 0) AS service_fee_inr,
    ROUND(COALESCE(mvf.vendor_fee_paise, 0) / 100.0, 0) AS vendor_fee_inr,
    ROUND((COALESCE(ms.subscription_rev_paise, 0) + COALESCE(mt.service_fee_paise, 0) + COALESCE(mvf.vendor_fee_paise, 0)) / 100.0, 0) AS total_revenue_inr,
    ROUND((COALESCE(mt.mdr_cost_paise, 0) + COALESCE(mt.pinelabs_cost_paise, 0)) / 100.0, 0) AS variable_cost_inr,
    COALESCE(ms.new_couples, 0)                      AS new_couples,
    COALESCE(mt.txn_count, 0)                        AS gift_transactions
FROM monthly_txns mt
FULL OUTER JOIN monthly_subscriptions ms ON ms.month = mt.month
FULL OUTER JOIN monthly_vendor_fees mvf ON mvf.month = mt.month
ORDER BY 1 DESC;

-- -----------------------------------------------
-- 10. AMAZON PAY NEW USER ACQUISITION VIA WEDDINGPAY
-- -----------------------------------------------
-- Guests who created Amazon Pay account for first time through WeddingPay
SELECT
    DATE_TRUNC('month', gt.created_at)              AS month,
    COUNT(DISTINCT g.guest_id) FILTER (
        WHERE gt.payment_gateway = 'amazon_pay'
        AND g.is_first_amazon_pay_txn = TRUE       -- flag set by payment gateway webhook
    )                                               AS new_amazon_pay_users,
    COUNT(DISTINCT g.guest_id) FILTER (
        WHERE gt.payment_gateway = 'amazon_pay'
    )                                               AS total_amazon_pay_gifts,
    ROUND(
        COUNT(DISTINCT g.guest_id) FILTER (WHERE gt.payment_gateway = 'amazon_pay' AND g.is_first_amazon_pay_txn = TRUE) * 100.0
        / NULLIF(COUNT(DISTINCT g.guest_id) FILTER (WHERE gt.payment_gateway = 'amazon_pay'), 0), 1
    )                                               AS new_user_rate_pct
FROM gift_transaction gt
JOIN guest g ON g.guest_id = gt.guest_id
WHERE gt.status = 'success'
GROUP BY 1
ORDER BY 1 DESC;
