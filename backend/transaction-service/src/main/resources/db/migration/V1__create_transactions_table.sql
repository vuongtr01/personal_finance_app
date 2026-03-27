CREATE TABLE transactions (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT NOT NULL,
    type              VARCHAR(10) NOT NULL CHECK (type IN ('INCOME', 'EXPENSE')),
    amount            NUMERIC(12,2) NOT NULL,
    category_id       BIGINT,
    description       VARCHAR(500),
    transaction_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transactions_user_date ON transactions(user_id, transaction_date DESC);
CREATE INDEX idx_transactions_user_category ON transactions(user_id, category_id);
