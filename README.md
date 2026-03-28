# 💍 WeddingPay
### *Powered by Amazon Pay Gift Cards*

> **B2B2C SaaS platform transforming India's ₹80,000 Cr wedding gifting market into a structured, trackable, premium digital journey.**

---

## 📁 Repository Structure

```
weddingpay/
├── prototype/
│   ├── couple_view.html        # Couple Dashboard prototype (leadership demo)
│   └── guest_view.html         # Guest Registry & Gifting experience
├── prd/
│   └── WeddingPay_PRD.md       # Full Product Requirements Document
├── data/
│   ├── schema.sql              # PostgreSQL schema — all core entities
│   ├── analytics_queries.sql   # Redshift analytics queries (KPIs, funnels)
│   └── unit_economics.R        # R model for unit economics & projections
├── docs/
│   └── WeddingPay_Blueprint.docx  # Original product blueprint (HLD + LLD + Financials)
└── README.md
```

---

## 🎯 Product Vision

WeddingPay captures India's undigitised wedding gifting flow and routes it through Amazon Pay infrastructure — generating margin-accretive revenue without entering a discount-led competitive dynamic.

| Dimension | Detail |
|-----------|--------|
| Revenue Model | Couple SaaS subscription + Amazon Pay service fee + float + vendor payment fee |
| Buyer Psychology | Outcome buyer (memorable wedding) — not price buyer |
| Competitive Moat | No existing platform competes in this segment |
| Amazon's Role | Infrastructure & brand — never the direct contracting entity |
| Distribution | Embedded in WedMeGood, destination platforms, luxury planners |

---

## 🖥️ Prototype Views

### Couple Dashboard (`prototype/couple_view.html`)
- Gift Pool Wallet with Amazon Pay balance visualisation
- Registry Builder (Nest / Wander / Celebrate / Bless categories)
- Real-time guest contribution tracker with media messages
- Vendor Console — pay caterers, decorators, photographers from gift balance
- Invitation share panel with WhatsApp / Email / QR Code
- Wedding Story Microsite preview

### Guest Registry (`prototype/guest_view.html`)
- Immersive wedding story hero page (no app, no login required)
- Registry category cards with live funding progress
- Contribution flow: amount selection → guest details → media attachment → payment
- Payment via Amazon Pay / UPI / Card
- Instant personalised thank-you from the couple

---

## 📊 Subscription Plans

| Feature | Classic ₹4,999 | Premium ₹9,999 | Luxury ₹24,999 |
|---------|---------------|----------------|----------------|
| Registry Builder | ✓ | ✓ | ✓ |
| Wedding Story Microsite | Standard | Custom | Bespoke |
| Gift Pool Aggregation | ✓ | ✓ | ✓ |
| Vendor Payment Console | ✓ | ✓ | ✓ |
| Guest Video/Voice Messages | ✗ | ✓ | ✓ |
| Custom Domain | ✗ | ✓ | ✓ |
| Concierge Onboarding | ✗ | ✗ | ✓ |
| Physical Unboxing Kit | ✗ | ✗ | ✓ |

---

## 💰 Unit Economics (Base Case)

| Metric | Value |
|--------|-------|
| Avg subscription revenue | ₹9,500 |
| Avg gift pool per wedding | ₹4,50,000 |
| Amazon Pay service fee (0.5%) | ₹2,250 |
| Float income (60-day, 6% p.a.) | ₹4,438 |
| Vendor payment fee (0.5%) | ₹1,125 |
| **Gross revenue per wedding** | **₹17,313** |
| Net margin per wedding | ₹7,103 (41%) |

### 3-Year Projections
| Year | Weddings | Gross Revenue | Net Profit |
|------|----------|---------------|------------|
| Y1 | 5,000 | ₹6.6 Cr | ₹1.3 Cr |
| Y2 | 25,000 | ₹33.0 Cr | ₹14.0 Cr |
| Y3 | 75,000 | ₹99.0 Cr | ₹52.0 Cr |

---

## 🏗️ Architecture Overview

```
Presentation     →  React.js (web) + React Native (mobile)
API Gateway      →  AWS API Gateway + Lambda
Application      →  Node.js microservices on AWS ECS (Fargate)
Payment Infra    →  Pinelabs API + Amazon Pay PG
Data Layer       →  PostgreSQL (RDS) + Redshift
Notifications    →  AWS SNS + SES + WhatsApp Business API
Security         →  AWS Cognito + Tokenisation + DPDP Act compliance
```

---

## 🚀 Go-To-Market

- **Phase 1 (M1–6):** Anchor partner — WedMeGood (50L+ monthly users)
- **Phase 2 (M4–9):** Luxury & destination wedding platforms (Taj, Oberoi)
- **Phase 3 (M10+):** Direct-to-couple via weddingpay.in + Vendor Network

---

## 📋 KPIs (Year 1 Targets)

| Metric | Target |
|--------|--------|
| Couple Activations | 5,000 |
| Gift Pool per Wedding | ₹3,50,000 |
| Guest Gifting Rate | 35% |
| Vendor Payment Adoption | 40% |
| Amazon Pay New Users via Platform | 25,000 |
| Float AUM | ₹15 Cr |

---

*Confidential — Amazon Pay Gift Cards Business · March 2026*
