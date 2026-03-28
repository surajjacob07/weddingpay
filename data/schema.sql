-- ============================================================
-- WeddingPay — PostgreSQL Schema
-- Version: 1.0 | March 2026
-- DB: PostgreSQL 15 (AWS RDS ap-south-1)
-- ============================================================

-- -----------------------------------------------
-- EXTENSIONS
-- -----------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------
-- ENUMS
-- -----------------------------------------------
CREATE TYPE plan_tier AS ENUM ('classic', 'premium', 'luxury');
CREATE TYPE subscription_status AS ENUM ('active', 'expired', 'cancelled', 'trial');
CREATE TYPE registry_category AS ENUM ('nest', 'wander', 'celebrate', 'bless', 'surprise');
CREATE TYPE txn_status AS ENUM ('initiated', 'success', 'failed', 'refunded', 'pending');
CREATE TYPE payment_status AS ENUM ('initiated', 'escrow', 'settled', 'disputed', 'refunded');
CREATE TYPE vendor_type AS ENUM ('caterer', 'decorator', 'photographer', 'venue', 'music', 'mehendi', 'other');
CREATE TYPE kyc_status AS ENUM ('pending', 'verified', 'rejected', 'under_review');
CREATE TYPE partner_type AS ENUM ('aggregator', 'planner', 'hotel', 'destination_platform');
CREATE TYPE invitation_status AS ENUM ('sent', 'opened', 'gifted', 'not_sent');

-- -----------------------------------------------
-- PARTNER (Aggregators, Planners, Hotels)
-- -----------------------------------------------
CREATE TABLE partner (
    partner_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(200) NOT NULL,
    type                partner_type NOT NULL,
    revenue_share_pct   DECIMAL(5,2) DEFAULT 18.00,
    sdk_key             VARCHAR(128) UNIQUE NOT NULL,
    webhook_url         VARCHAR(500),
    white_label_color   VARCHAR(7),          -- hex colour for co-branding
    white_label_logo    VARCHAR(500),         -- S3 URL
    contract_value_inr  BIGINT,              -- annual white-label fee
    is_active           BOOLEAN DEFAULT TRUE,
    onboarded_at        TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_partner_sdk_key ON partner(sdk_key);

-- -----------------------------------------------
-- COUPLE
-- -----------------------------------------------
CREATE TABLE couple (
    couple_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_1              VARCHAR(100) NOT NULL,
    name_2              VARCHAR(100) NOT NULL,
    email_1             VARCHAR(200),
    email_2             VARCHAR(200),
    phone_1             VARCHAR(15) NOT NULL,
    phone_2             VARCHAR(15),
    wedding_date        DATE NOT NULL,
    venue_city          VARCHAR(100),
    venue_name          VARCHAR(200),
    slug                VARCHAR(100) UNIQUE,     -- aanya-rohan-2026
    custom_domain       VARCHAR(200) UNIQUE,     -- aanya-rohan.weddingpay.in
    plan_tier           plan_tier NOT NULL DEFAULT 'classic',
    subscription_status subscription_status DEFAULT 'active',
    subscription_paid_at TIMESTAMPTZ,
    subscription_expires_at TIMESTAMPTZ,
    gift_wallet_id      UUID,                    -- FK to gift_wallet
    partner_id          UUID REFERENCES partner(partner_id),
    love_story          TEXT,                    -- couple's story for microsite
    cover_photo_url     VARCHAR(500),
    kyc_status          kyc_status DEFAULT 'pending',
    pan_verified        BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_couple_slug ON couple(slug);
CREATE INDEX idx_couple_wedding_date ON couple(wedding_date);
CREATE INDEX idx_couple_partner ON couple(partner_id);
CREATE INDEX idx_couple_plan ON couple(plan_tier);

-- -----------------------------------------------
-- GIFT WALLET (Amazon Pay Gift Card Aggregator)
-- -----------------------------------------------
CREATE TABLE gift_wallet (
    wallet_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    couple_id           UUID UNIQUE NOT NULL REFERENCES couple(couple_id),
    total_issued_paise  BIGINT DEFAULT 0,        -- sum of all gift cards issued
    total_redeemed_paise BIGINT DEFAULT 0,       -- sum redeemed (vendor payments)
    available_balance_paise BIGINT GENERATED ALWAYS AS (total_issued_paise - total_redeemed_paise) STORED,
    pinelabs_wallet_ref VARCHAR(200) UNIQUE,     -- Pinelabs internal ref
    cards_count         INT DEFAULT 0,
    float_income_paise  BIGINT DEFAULT 0,        -- accrued float income
    last_updated        TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE couple ADD CONSTRAINT fk_couple_wallet FOREIGN KEY (gift_wallet_id) REFERENCES gift_wallet(wallet_id);

CREATE INDEX idx_wallet_couple ON gift_wallet(couple_id);
CREATE INDEX idx_wallet_balance ON gift_wallet(available_balance_paise);

-- -----------------------------------------------
-- REGISTRY
-- -----------------------------------------------
CREATE TABLE registry (
    registry_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    couple_id           UUID NOT NULL REFERENCES couple(couple_id),
    category            registry_category NOT NULL,
    title               VARCHAR(200) NOT NULL,
    description         TEXT,
    target_amount_paise BIGINT NOT NULL,
    contributed_amount_paise BIGINT DEFAULT 0,
    is_fulfilled        BOOLEAN GENERATED ALWAYS AS (contributed_amount_paise >= target_amount_paise) STORED,
    display_order       INT DEFAULT 0,
    emoji               VARCHAR(10),
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_registry_couple ON registry(couple_id);
CREATE INDEX idx_registry_category ON registry(category);

-- -----------------------------------------------
-- GUEST
-- -----------------------------------------------
CREATE TABLE guest (
    guest_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    couple_id           UUID NOT NULL REFERENCES couple(couple_id),
    name                VARCHAR(200) NOT NULL,
    phone               VARCHAR(15),
    email               VARCHAR(200),
    relation_tag        VARCHAR(50),             -- friend, family_bride, family_groom etc.
    invitation_status   invitation_status DEFAULT 'not_sent',
    invited_at          TIMESTAMPTZ,
    opened_at           TIMESTAMPTZ,
    gifted_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_guest_couple ON guest(couple_id);
CREATE INDEX idx_guest_phone ON guest(phone);
CREATE INDEX idx_guest_status ON guest(invitation_status);

-- -----------------------------------------------
-- GIFT TRANSACTION (Guest → Registry → Pinelabs card issuance)
-- -----------------------------------------------
CREATE TABLE gift_transaction (
    txn_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    couple_id           UUID NOT NULL REFERENCES couple(couple_id),
    registry_id         UUID REFERENCES registry(registry_id),
    guest_id            UUID REFERENCES guest(guest_id),
    amount_paise        BIGINT NOT NULL,
    currency            CHAR(3) DEFAULT 'INR',
    status              txn_status DEFAULT 'initiated',
    -- Pinelabs gift card
    pinelabs_card_ref   VARCHAR(200),
    pinelabs_card_code  VARCHAR(200),            -- encrypted at rest
    card_issued_at      TIMESTAMPTZ,
    -- Guest payment
    payment_gateway     VARCHAR(50),             -- amazon_pay / upi / card
    pg_txn_ref          VARCHAR(200),
    -- Media
    media_type          VARCHAR(20),             -- video / voice / text
    media_attachment_url VARCHAR(500),           -- S3 URL
    guest_message       TEXT,
    -- Auto thank-you
    thankyou_sent_at    TIMESTAMPTZ,
    -- MDR and costs
    mdr_paise           BIGINT DEFAULT 0,        -- ~1.8% on guest payment
    pinelabs_fee_paise  BIGINT DEFAULT 0,        -- ~₹4 per card
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_txn_couple ON gift_transaction(couple_id);
CREATE INDEX idx_txn_registry ON gift_transaction(registry_id);
CREATE INDEX idx_txn_guest ON gift_transaction(guest_id);
CREATE INDEX idx_txn_status ON gift_transaction(status);
CREATE INDEX idx_txn_created ON gift_transaction(created_at DESC);

-- -----------------------------------------------
-- VENDOR
-- -----------------------------------------------
CREATE TABLE vendor (
    vendor_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(200) NOT NULL,
    type                vendor_type NOT NULL,
    kyc_status          kyc_status DEFAULT 'pending',
    aadhaar_verified    BOOLEAN DEFAULT FALSE,
    gst_number          VARCHAR(20),
    gst_verified        BOOLEAN DEFAULT FALSE,
    bank_account_id     VARCHAR(200),
    ifsc_code           CHAR(11),
    account_name        VARCHAR(200),
    amazon_pay_id       VARCHAR(200),
    phone               VARCHAR(15),
    email               VARCHAR(200),
    onboarded_by_couple_id UUID REFERENCES couple(couple_id),
    is_certified        BOOLEAN DEFAULT FALSE,   -- WeddingPay Certified Vendor
    rating              DECIMAL(3,2),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_vendor_type ON vendor(type);
CREATE INDEX idx_vendor_kyc ON vendor(kyc_status);
CREATE INDEX idx_vendor_certified ON vendor(is_certified);

-- -----------------------------------------------
-- VENDOR PAYMENT (Couple wallet → Vendor)
-- -----------------------------------------------
CREATE TABLE vendor_payment (
    payment_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    couple_id           UUID NOT NULL REFERENCES couple(couple_id),
    vendor_id           UUID NOT NULL REFERENCES vendor(vendor_id),
    amount_paise        BIGINT NOT NULL,
    status              payment_status DEFAULT 'initiated',
    -- Pinelabs redemption
    pinelabs_redemption_ref VARCHAR(200),
    wallet_debited_at   TIMESTAMPTZ,
    -- Escrow
    escrow_at           TIMESTAMPTZ,
    escrow_expires_at   TIMESTAMPTZ,             -- escrow_at + 24h
    -- Settlement
    settled_at          TIMESTAMPTZ,
    settlement_mode     VARCHAR(20),             -- IMPS / NEFT / amazon_pay
    utr_number          VARCHAR(50),             -- settlement UTR
    -- Fees
    vendor_fee_paise    BIGINT DEFAULT 0,        -- 0.5% min ₹25
    -- Receipts & docs
    receipt_url         VARCHAR(500),            -- S3 URL (GST receipt PDF)
    couple_notes        TEXT,
    -- Dispute
    disputed_at         TIMESTAMPTZ,
    dispute_reason      TEXT,
    dispute_resolved_at TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_vpayment_couple ON vendor_payment(couple_id);
CREATE INDEX idx_vpayment_vendor ON vendor_payment(vendor_id);
CREATE INDEX idx_vpayment_status ON vendor_payment(status);
CREATE INDEX idx_vpayment_escrow ON vendor_payment(escrow_expires_at) WHERE status = 'escrow';

-- -----------------------------------------------
-- PLATFORM EVENTS (audit log / analytics feed)
-- -----------------------------------------------
CREATE TABLE platform_event (
    event_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type          VARCHAR(100) NOT NULL,   -- couple.signup, gift.sent, vendor.paid etc.
    couple_id           UUID REFERENCES couple(couple_id),
    guest_id            UUID REFERENCES guest(guest_id),
    vendor_id           UUID REFERENCES vendor(vendor_id),
    partner_id          UUID REFERENCES partner(partner_id),
    amount_paise        BIGINT,
    metadata            JSONB,
    created_at          TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Monthly partitions
CREATE TABLE platform_event_2026_01 PARTITION OF platform_event FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE platform_event_2026_02 PARTITION OF platform_event FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE platform_event_2026_03 PARTITION OF platform_event FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE platform_event_2026_04 PARTITION OF platform_event FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE platform_event_2026_05 PARTITION OF platform_event FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE platform_event_2026_06 PARTITION OF platform_event FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE platform_event_2026_q3  PARTITION OF platform_event FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');
CREATE TABLE platform_event_2026_q4  PARTITION OF platform_event FOR VALUES FROM ('2026-10-01') TO ('2027-01-01');

CREATE INDEX idx_event_type ON platform_event(event_type, created_at DESC);
CREATE INDEX idx_event_couple ON platform_event(couple_id, created_at DESC);

-- -----------------------------------------------
-- TRIGGERS: auto-update wallet on gift transaction
-- -----------------------------------------------
CREATE OR REPLACE FUNCTION update_wallet_on_gift()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'success' AND OLD.status != 'success' THEN
        UPDATE gift_wallet
        SET total_issued_paise = total_issued_paise + NEW.amount_paise,
            cards_count = cards_count + 1,
            last_updated = NOW()
        WHERE couple_id = NEW.couple_id;

        UPDATE registry
        SET contributed_amount_paise = contributed_amount_paise + NEW.amount_paise,
            updated_at = NOW()
        WHERE registry_id = NEW.registry_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_wallet_on_gift
    AFTER UPDATE ON gift_transaction
    FOR EACH ROW EXECUTE FUNCTION update_wallet_on_gift();

-- Trigger: update wallet on vendor payment settlement
CREATE OR REPLACE FUNCTION update_wallet_on_vendor_payment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'settled' AND OLD.status != 'settled' THEN
        UPDATE gift_wallet
        SET total_redeemed_paise = total_redeemed_paise + NEW.amount_paise,
            last_updated = NOW()
        WHERE couple_id = NEW.couple_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_wallet_on_vendor_payment
    AFTER UPDATE ON vendor_payment
    FOR EACH ROW EXECUTE FUNCTION update_wallet_on_vendor_payment();

-- -----------------------------------------------
-- VIEWS: operational dashboards
-- -----------------------------------------------

-- Couple-level gift summary
CREATE VIEW v_couple_gift_summary AS
SELECT
    c.couple_id,
    c.name_1 || ' & ' || c.name_2 AS couple_name,
    c.wedding_date,
    c.plan_tier,
    c.partner_id,
    gw.available_balance_paise,
    gw.total_issued_paise,
    gw.total_redeemed_paise,
    gw.cards_count,
    COUNT(DISTINCT g.guest_id) FILTER (WHERE g.invitation_status = 'gifted') AS guests_gifted,
    COUNT(DISTINCT vp.payment_id) FILTER (WHERE vp.status = 'settled') AS vendor_payments_settled,
    SUM(vp.amount_paise) FILTER (WHERE vp.status = 'settled') AS vendor_paid_paise
FROM couple c
LEFT JOIN gift_wallet gw ON gw.couple_id = c.couple_id
LEFT JOIN guest g ON g.couple_id = c.couple_id
LEFT JOIN vendor_payment vp ON vp.couple_id = c.couple_id
GROUP BY c.couple_id, c.name_1, c.name_2, c.wedding_date, c.plan_tier, c.partner_id,
         gw.available_balance_paise, gw.total_issued_paise, gw.total_redeemed_paise, gw.cards_count;

-- Daily revenue summary for finance team
CREATE VIEW v_daily_revenue AS
SELECT
    DATE(gt.created_at) AS txn_date,
    COUNT(*) AS total_txns,
    SUM(gt.amount_paise) / 100.0 AS total_gift_pool_inr,
    SUM(gt.amount_paise) * 0.005 / 100.0 AS service_fee_inr,   -- 0.5% service fee
    SUM(gt.mdr_paise) / 100.0 AS mdr_cost_inr,
    SUM(gt.pinelabs_fee_paise) / 100.0 AS pinelabs_cost_inr
FROM gift_transaction gt
WHERE gt.status = 'success'
GROUP BY DATE(gt.created_at)
ORDER BY txn_date DESC;
