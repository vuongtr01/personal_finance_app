CREATE TABLE budget_categories (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT NOT NULL,
    name              VARCHAR(100) NOT NULL,
    description       VARCHAR(500),
    allocated_amount  NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    spent_amount      NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, name)
);

CREATE TABLE allocations (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL,
    category_id     BIGINT NOT NULL REFERENCES budget_categories(id),
    amount          NUMERIC(12,2) NOT NULL,
    description     VARCHAR(500),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE category_transfers (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT NOT NULL,
    from_category_id  BIGINT NOT NULL REFERENCES budget_categories(id),
    to_category_id    BIGINT NOT NULL REFERENCES budget_categories(id),
    amount            NUMERIC(12,2) NOT NULL,
    note              VARCHAR(500),
    created_at        TIMESTAMP NOT NULL DEFAULT NOW()
);
