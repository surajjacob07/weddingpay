# ============================================================
# WeddingPay — Unit Economics & Financial Projections
# Language: R | March 2026
# ============================================================

library(tidyverse)
library(scales)
library(ggplot2)
library(knitr)

# -----------------------------------------------
# 1. SUBSCRIPTION PLAN PARAMETERS
# -----------------------------------------------
plans <- tibble(
  tier               = c("Classic", "Premium", "Luxury"),
  price_inr          = c(4999, 9999, 24999),
  # Revenue share to aggregator partner
  partner_share_pct  = c(0.18, 0.18, 0.18)
)

# -----------------------------------------------
# 2. SCENARIO ASSUMPTIONS
# -----------------------------------------------
scenarios <- tibble(
  scenario           = c("Conservative", "Base Case", "Optimistic"),
  plan_mix_classic   = c(0.60, 0.40, 0.20),
  plan_mix_premium   = c(0.35, 0.45, 0.50),
  plan_mix_luxury    = c(0.05, 0.15, 0.30),
  avg_gift_pool_inr  = c(250000, 450000, 750000),
  service_fee_pct    = c(0.005, 0.005, 0.005),
  float_rate_annual  = c(0.06, 0.06, 0.06),
  float_days         = c(60, 60, 60),
  vendor_pmt_pct     = c(0.50, 0.50, 0.50),   # % of gift pool used for vendor payments
  vendor_fee_pct     = c(0.005, 0.005, 0.005),
  # Costs
  mdr_pct            = c(0.018, 0.018, 0.018),
  pinelabs_fee_inr   = c(4, 4, 4),            # per card issued
  avg_guests_gifting = c(50, 84, 130)
)

# -----------------------------------------------
# 3. UNIT ECONOMICS CALCULATION
# -----------------------------------------------
unit_economics <- scenarios %>%
  mutate(
    # Weighted avg subscription revenue
    avg_subscription_rev = plan_mix_classic * 4999 +
                           plan_mix_premium * 9999 +
                           plan_mix_luxury  * 24999,

    # Revenue lines
    amazon_pay_service_fee  = avg_gift_pool_inr * service_fee_pct,
    float_income            = avg_gift_pool_inr * float_rate_annual * float_days / 365,
    vendor_payment_volume   = avg_gift_pool_inr * vendor_pmt_pct,
    vendor_fee_rev          = pmax(vendor_payment_volume * vendor_fee_pct, 25),  # min ₹25
    gross_revenue_per_wedding = avg_subscription_rev + amazon_pay_service_fee +
                                float_income + vendor_fee_rev,

    # Costs
    partner_payout          = avg_subscription_rev * 0.18,
    mdr_cost                = avg_gift_pool_inr * mdr_pct,
    pinelabs_cost           = pinelabs_fee_inr * avg_guests_gifting,
    total_variable_cost     = partner_payout + mdr_cost + pinelabs_cost,

    # Net margin
    net_margin_per_wedding  = gross_revenue_per_wedding - total_variable_cost,
    net_margin_pct          = net_margin_per_wedding / gross_revenue_per_wedding
  ) %>%
  select(scenario, avg_subscription_rev, amazon_pay_service_fee, float_income,
         vendor_fee_rev, gross_revenue_per_wedding, total_variable_cost,
         net_margin_per_wedding, net_margin_pct)

cat("\n========== UNIT ECONOMICS PER WEDDING ==========\n")
unit_economics %>%
  mutate(across(where(is.numeric), ~ifelse(. < 1, scales::percent(., 0.1), scales::comma(round(., 0))))) %>%
  knitr::kable(format = "simple", align = "r")

# -----------------------------------------------
# 4. BREAK-EVEN ANALYSIS
# -----------------------------------------------
# Fixed costs per year
fixed_costs <- list(
  aws_infra_inr      = 6000000,   # ₹60L
  customer_support   = 20000000,  # ₹2Cr at 20K weddings scale
  sales_team         = 12500000,  # ₹1.25Cr
  total              = 38500000   # ~₹3.85Cr
)

breakeven_analysis <- unit_economics %>%
  mutate(
    fixed_cost_annual      = fixed_costs$total,
    breakeven_weddings     = ceiling(fixed_costs$total / net_margin_per_wedding),
    breakeven_weddings_monthly = ceiling(breakeven_weddings / 12)
  ) %>%
  select(scenario, net_margin_per_wedding, breakeven_weddings, breakeven_weddings_monthly)

cat("\n========== BREAK-EVEN ANALYSIS ==========\n")
print(breakeven_analysis)

# -----------------------------------------------
# 5. 3-YEAR SCALE PROJECTIONS
# -----------------------------------------------
projections <- crossing(
  year   = 1:3,
  scenario = c("Conservative", "Base Case", "Optimistic")
) %>%
  mutate(
    # Wedding volume ramp
    weddings = case_when(
      scenario == "Conservative" & year == 1 ~ 3000,
      scenario == "Conservative" & year == 2 ~ 15000,
      scenario == "Conservative" & year == 3 ~ 50000,
      scenario == "Base Case"    & year == 1 ~ 5000,
      scenario == "Base Case"    & year == 2 ~ 25000,
      scenario == "Base Case"    & year == 3 ~ 75000,
      scenario == "Optimistic"   & year == 1 ~ 8000,
      scenario == "Optimistic"   & year == 2 ~ 40000,
      scenario == "Optimistic"   & year == 3 ~ 120000
    ),
    # Net margin per wedding grows as efficiency improves
    net_margin_per_wedding = case_when(
      scenario == "Conservative" & year == 1 ~ 4876,
      scenario == "Conservative" & year == 2 ~ 5500,
      scenario == "Conservative" & year == 3 ~ 6500,
      scenario == "Base Case"    & year == 1 ~ 7103,
      scenario == "Base Case"    & year == 2 ~ 8000,
      scenario == "Base Case"    & year == 3 ~ 10000,
      scenario == "Optimistic"   & year == 1 ~ 10916,
      scenario == "Optimistic"   & year == 2 ~ 14000,
      scenario == "Optimistic"   & year == 3 ~ 18000
    )
  ) %>%
  left_join(
    unit_economics %>% select(scenario, gross_revenue_per_wedding),
    by = "scenario"
  ) %>%
  mutate(
    total_revenue_cr   = weddings * gross_revenue_per_wedding / 10000000,
    net_profit_cr      = weddings * net_margin_per_wedding / 10000000,
    fixed_cost_cr      = case_when(
      year == 1 ~ 5.00,
      year == 2 ~ 19.00,
      year == 3 ~ 47.00
    ),
    # Float AUM
    avg_gift_pool      = case_when(
      scenario == "Conservative" ~ 250000,
      scenario == "Base Case"    ~ 450000,
      scenario == "Optimistic"   ~ 750000
    ),
    float_aum_cr       = weddings * avg_gift_pool * 60 / 365 / 10000000,  # 60-day outstanding
    net_margin_pct     = net_profit_cr / total_revenue_cr
  )

cat("\n========== 3-YEAR PROJECTIONS (Base Case) ==========\n")
projections %>%
  filter(scenario == "Base Case") %>%
  select(year, weddings, total_revenue_cr, net_profit_cr, float_aum_cr, net_margin_pct) %>%
  mutate(
    total_revenue_cr = paste0("₹", round(total_revenue_cr, 1), " Cr"),
    net_profit_cr    = paste0("₹", round(net_profit_cr, 1), " Cr"),
    float_aum_cr     = paste0("₹", round(float_aum_cr, 1), " Cr"),
    net_margin_pct   = scales::percent(net_margin_pct, 1)
  ) %>%
  knitr::kable(format = "simple")

# -----------------------------------------------
# 6. SENSITIVITY ANALYSIS — Net Margin vs Key Drivers
# -----------------------------------------------
sensitivity_gift_pool <- seq(100000, 1000000, by = 50000)

sensitivity_df <- tibble(
  gift_pool_inr     = sensitivity_gift_pool,
  service_fee       = gift_pool_inr * 0.005,
  float_income      = gift_pool_inr * 0.06 * 60 / 365,
  vendor_fee        = gift_pool_inr * 0.50 * 0.005,
  gross_rev         = 9500 + service_fee + float_income + vendor_fee,  # Base subscription
  variable_cost     = 1710 + gift_pool_inr * 0.018 + 4 * 84,          # Base scenario costs
  net_margin        = gross_rev - variable_cost,
  net_margin_pct    = net_margin / gross_rev
)

cat("\n========== SENSITIVITY: NET MARGIN vs GIFT POOL SIZE ==========\n")
sensitivity_df %>%
  filter(gift_pool_inr %in% c(100000, 250000, 450000, 750000, 1000000)) %>%
  select(gift_pool_inr, gross_rev, net_margin, net_margin_pct) %>%
  mutate(across(c(gift_pool_inr, gross_rev, net_margin), ~scales::comma(round(., 0))),
         net_margin_pct = scales::percent(net_margin_pct, 1)) %>%
  knitr::kable(format = "simple")

# -----------------------------------------------
# 7. VISUALIZATION: Revenue Waterfall (Base Case)
# -----------------------------------------------
base_case_waterfall <- tibble(
  component = c(
    "Subscription Revenue",
    "+ Amazon Pay Service Fee",
    "+ Float Income",
    "+ Vendor Payment Fee",
    "= Gross Revenue",
    "- Partner Payout",
    "- MDR Cost",
    "- Pinelabs Cost",
    "= Net Margin"
  ),
  value = c(9500, 2250, 4438, 1125, 17313, -1710, -8100, -400, 7103),
  type  = c("revenue","revenue","revenue","revenue","total","cost","cost","cost","margin")
)

p_waterfall <- ggplot(base_case_waterfall, aes(
  x     = reorder(component, seq_along(component)),
  y     = value,
  fill  = type
)) +
  geom_col(width = 0.65) +
  geom_text(aes(label = paste0("₹", scales::comma(abs(value)))),
            hjust = -0.1, size = 3.2) +
  coord_flip() +
  scale_fill_manual(values = c(
    "revenue" = "#C9A84C",
    "total"   = "#3D2B1F",
    "cost"    = "#CC6666",
    "margin"  = "#5C8C6A"
  )) +
  scale_y_continuous(labels = scales::comma_format(prefix = "₹")) +
  labs(
    title    = "WeddingPay — Per-Wedding Revenue Waterfall (Base Case)",
    subtitle = "Average gift pool ₹4.5L | Premium plan mix 45%",
    x        = NULL, y = "Amount (₹)",
    caption  = "Source: WeddingPay Financial Model v1.0 | March 2026"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position  = "none",
    plot.title       = element_text(face = "bold", size = 14),
    panel.grid.major.y = element_blank()
  )

# Save chart
ggsave("weddingpay_waterfall.png", p_waterfall, width = 10, height = 6, dpi = 150)
cat("\nWaterfall chart saved to weddingpay_waterfall.png\n")

# -----------------------------------------------
# 8. GUEST GIFTING RATE SIMULATION (Monte Carlo)
# -----------------------------------------------
set.seed(42)
n_simulations <- 10000
guests_per_wedding <- 240

# Simulate guest gifting decisions (Bernoulli with p=0.35 base)
simulate_gift_pool <- function(n_sim, n_guests, p_gift, mean_gift, sd_gift) {
  replicate(n_sim, {
    gifting_guests <- rbinom(1, n_guests, p_gift)
    gift_amounts   <- rlnorm(gifting_guests, meanlog = log(mean_gift), sdlog = 0.5)
    sum(gift_amounts)
  })
}

gift_pool_sims <- simulate_gift_pool(
  n_sim    = n_simulations,
  n_guests = guests_per_wedding,
  p_gift   = 0.35,
  mean_gift = 5000,
  sd_gift   = 3000
)

cat("\n========== MONTE CARLO: GIFT POOL SIMULATION (n=10,000) ==========\n")
cat(sprintf("Mean gift pool:     ₹%s\n", scales::comma(round(mean(gift_pool_sims)))))
cat(sprintf("Median gift pool:   ₹%s\n", scales::comma(round(median(gift_pool_sims)))))
cat(sprintf("P10 (downside):     ₹%s\n", scales::comma(round(quantile(gift_pool_sims, 0.10)))))
cat(sprintf("P90 (upside):       ₹%s\n", scales::comma(round(quantile(gift_pool_sims, 0.90)))))
cat(sprintf("Prob > ₹4.5L:       %.1f%%\n", mean(gift_pool_sims > 450000) * 100))
cat(sprintf("Prob > ₹7.5L:       %.1f%%\n", mean(gift_pool_sims > 750000) * 100))

# -----------------------------------------------
# 9. KPI DASHBOARD SUMMARY
# -----------------------------------------------
cat("\n========== YEAR 1 KPI TARGETS (Base Case) ==========\n")
kpi_targets <- tibble(
  KPI                         = c(
    "Couple Activations",
    "Avg Gift Pool per Wedding",
    "Guest Gifting Rate",
    "Vendor Payment Adoption",
    "Subscription Upgrade Rate",
    "Partner SDK Activations",
    "Float AUM",
    "Amazon Pay New User Acquisitions",
    "Gross Revenue",
    "Net Profit"
  ),
  Target = c(
    "5,000 couples",
    "₹3,50,000",
    "35%",
    "40%",
    "20%",
    "3 partners",
    "₹15 Cr",
    "25,000 users",
    "₹6.6 Cr",
    "₹1.3 Cr"
  )
)
knitr::kable(kpi_targets, format = "simple")

cat("\n\nWeddingPay Financial Model v1.0 — Complete\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
