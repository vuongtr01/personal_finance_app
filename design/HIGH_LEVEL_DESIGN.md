# Personal Finance Tracking App — High Level Design

## 1. Overview

A microservices-based personal finance application that lets users allocate income into custom budget categories, track spending against those categories, and transfer money between categories when overspending occurs.

### Tech Stack
- **Frontend:** React 18 + TypeScript, Vite, Tailwind CSS, Zustand, Recharts
- **Backend:** Java 17, Spring Boot 3, Spring Cloud Gateway
- **Database:** PostgreSQL 16 (one instance, three logical databases)
- **Infrastructure:** Docker Compose

---

## 2. Architecture Diagram

```
┌──────────────┐         ┌──────────────────────────────────────────┐
│              │  HTTP    │            API Gateway (8080)            │
│   React SPA  │────────▶│   Spring Cloud Gateway                   │
│  (port 5173) │◀────────│   - Route forwarding                    │
│              │         │   - CORS handling                       │
└──────────────┘         └────────┬──────────┬──────────┬──────────┘
                                  │          │          │
                         /api/auth/*  /api/budgets/*  /api/transactions/*
                                  │          │          │
                    ┌─────────────┘          │          └─────────────┐
                    ▼                        ▼                        ▼
           ┌───────────────┐      ┌───────────────┐      ┌───────────────────┐
           │ User Service  │      │Budget Service  │      │Transaction Service│
           │   (8081)      │      │   (8082)       │◀─────│     (8083)        │
           │               │      │                │ HTTP  │                   │
           │ - Register    │      │ - Categories   │deduct/│ - Record income   │
           │ - Login       │      │ - Allocations  │refund │ - Record expense  │
           │ - JWT issuing │      │ - Transfers    │      │ - Spending history│
           └───────┬───────┘      └───────┬────────┘      └────────┬──────────┘
                   │                      │                         │
                   ▼                      ▼                         ▼
            ┌──────────┐          ┌───────────┐            ┌──────────────┐
            │ user_db  │          │ budget_db │            │transaction_db│
            └──────────┘          └───────────┘            └──────────────┘
                         PostgreSQL 16 (Docker)
```

### Inter-Service Communication
- **Synchronous HTTP** — Transaction Service calls Budget Service's internal endpoints to deduct/refund category balances
- **No service discovery** — services use configurable base URLs (`http://localhost:808x`)
- **Shared JWT secret** — each service independently validates JWT tokens using a common library

---

## 3. Database Schema

### 3.1 User Service — `user_db`

```sql
CREATE TABLE users (
    id              BIGSERIAL PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    display_name    VARCHAR(100) NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);
```

### 3.2 Budget Service — `budget_db`

```sql
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
```

**Balance calculation:** `remaining = allocated_amount - spent_amount` (stored directly on `budget_categories` to avoid expensive joins; updated atomically with `@Transactional`).

### 3.3 Transaction Service — `transaction_db`

```sql
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
```

---

## 4. API Endpoints

### 4.1 User Service — `/api/auth`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/register` | No | Create account, returns JWT |
| POST | `/api/auth/login` | No | Login, returns JWT |
| GET | `/api/auth/me` | Yes | Get current user profile |
| PUT | `/api/auth/me` | Yes | Update display name |

### 4.2 Budget Service — `/api/budgets`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/budgets/categories` | Yes | List all user categories |
| POST | `/api/budgets/categories` | Yes | Create a category |
| PUT | `/api/budgets/categories/{id}` | Yes | Update category name/description |
| DELETE | `/api/budgets/categories/{id}` | Yes | Delete category (balance must be 0) |
| POST | `/api/budgets/categories/{id}/allocate` | Yes | Allocate income amount to category |
| POST | `/api/budgets/transfers` | Yes | Transfer money between categories |
| GET | `/api/budgets/allocations` | Yes | Allocation history (?categoryId=) |
| GET | `/api/budgets/summary` | Yes | All categories with computed balances |

**Internal endpoints (not routed through gateway):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/internal/categories/{id}/deduct` | Deduct from spent_amount (called by Transaction Service) |
| POST | `/internal/categories/{id}/refund` | Refund to spent_amount (on expense deletion) |

### 4.3 Transaction Service — `/api/transactions`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/transactions/income` | Yes | Record income entry |
| POST | `/api/transactions/expense` | Yes | Record expense (triggers budget deduction) |
| GET | `/api/transactions` | Yes | List with filters: type, categoryId, startDate, endDate, pagination |
| GET | `/api/transactions/{id}` | Yes | Single transaction detail |
| DELETE | `/api/transactions/{id}` | Yes | Delete transaction (refunds category if expense) |
| GET | `/api/transactions/summary` | Yes | Monthly spending by category |

### Expense Recording Flow

```
Frontend                Gateway             Transaction Svc        Budget Svc
   │                      │                      │                     │
   │ POST /expense        │                      │                     │
   │─────────────────────▶│─────────────────────▶│                     │
   │                      │                      │ POST /internal/     │
   │                      │                      │ categories/{id}/    │
   │                      │                      │ deduct              │
   │                      │                      │────────────────────▶│
   │                      │                      │     200 OK          │
   │                      │                      │◀────────────────────│
   │                      │  Save transaction    │                     │
   │      201 Created     │◀─────────────────────│                     │
   │◀─────────────────────│                      │                     │
```

---

## 5. Frontend Design

### 5.1 Pages

| Route | Page | Description |
|-------|------|-------------|
| `/login` | LoginPage | Email/password login |
| `/register` | RegisterPage | Account creation |
| `/` | DashboardPage | Category balance chart, spending summary, recent transactions |
| `/categories` | CategoriesPage | Create/edit/delete budget categories |
| `/allocate` | AllocatePage | Allocate dollar amounts to categories |
| `/transactions` | TransactionsPage | Full transaction list with filters |
| `/transactions/new` | NewTransactionPage | Add income or expense |
| `/transfer` | TransferPage | Move money between categories |

### 5.2 State Management

Three Zustand stores:
- **authStore** — token, user, login/register/logout actions
- **budgetStore** — categories, summary, allocate/transfer actions
- **transactionStore** — transactions, filters, add/delete actions

### 5.3 Component Structure

```
src/
├── api/            # Axios client with JWT interceptor, per-service API modules
├── stores/         # authStore, budgetStore, transactionStore
├── pages/          # One component per route
├── components/
│   ├── layout/     # AppLayout, Sidebar, TopBar
│   ├── auth/       # LoginForm, RegisterForm, ProtectedRoute
│   ├── dashboard/  # BudgetOverviewChart, SpendingSummaryCard, RecentTransactions
│   ├── categories/ # CategoryList, CategoryForm, CategoryCard
│   ├── transactions/ # TransactionList, TransactionForm, TransactionFilters
│   ├── budget/     # AllocationForm, TransferForm, AllocationHistory
│   └── common/     # LoadingSpinner, ErrorAlert, ConfirmDialog, CurrencyDisplay
├── types/          # TypeScript interfaces
└── utils/          # formatCurrency, dateUtils
```

---

## 6. Project Structure

```
personal_finance_app/
├── design/                     # This document
├── docker-compose.yml          # PostgreSQL container (3 databases)
├── init-databases.sql          # CREATE DATABASE statements
├── backend/
│   ├── settings.gradle         # Multi-project build config
│   ├── build.gradle            # Root: shared dependency versions
│   ├── common/                 # Shared JWT util + auth filter
│   │   └── src/main/java/com/finance/common/security/
│   ├── api-gateway/            # Spring Cloud Gateway
│   │   └── src/main/resources/application.yml
│   ├── user-service/
│   │   └── src/main/java/com/finance/user/
│   │       ├── controller/
│   │       ├── dto/
│   │       ├── entity/
│   │       ├── repository/
│   │       ├── security/
│   │       └── service/
│   ├── budget-service/
│   │   └── src/main/java/com/finance/budget/
│   │       ├── controller/     # includes InternalCategoryController
│   │       ├── dto/
│   │       ├── entity/
│   │       ├── repository/
│   │       └── service/
│   └── transaction-service/
│       └── src/main/java/com/finance/transaction/
│           ├── client/         # BudgetServiceClient (HTTP)
│           ├── controller/
│           ├── dto/
│           ├── entity/
│           ├── repository/
│           └── service/
└── frontend/
    ├── package.json
    ├── vite.config.ts
    ├── tailwind.config.js
    └── src/
```

---

## 7. Implementation Phases

### Phase 1: Project Setup

**Goal:** All services bootable, databases running, frontend dev server running.

**Tasks:**
1. Initialize git repository with `.gitignore`
2. Create monorepo folder structure (backend + frontend directories)
3. Write `docker-compose.yml` — single PostgreSQL 16 container with volume persistence
4. Write `init-databases.sql` — creates `user_db`, `budget_db`, `transaction_db`
5. Create Gradle multi-project build:
   - `backend/settings.gradle` — includes all 5 subprojects
   - `backend/build.gradle` — shared Spring Boot 3.2+ and dependency versions
   - Individual `build.gradle` per service with specific dependencies
6. Generate Spring Boot application classes for each service
7. Configure `application.yml` per service (DB connection, server port, JWT secret)
8. Add Flyway migrations for each service's schema
9. Scaffold React app with `npm create vite@latest` (React + TypeScript template)
10. Install frontend dependencies: tailwindcss, react-router-dom, zustand, axios, recharts

**Verification:** `docker-compose up` starts PostgreSQL. Each Spring Boot service starts on its port. `npm run dev` starts frontend on port 5173.

**Deliverable:** Fully bootable skeleton — no business logic yet.

---

### Phase 2: User Service + Authentication

**Goal:** Users can register and log in. JWT tokens are issued and validated by all services.

**Tasks:**
1. Implement shared JWT library in `common/`:
   - `JwtUtil.java` — generate token (userId + email in claims, configurable expiry), validate token, extract userId
   - `JwtAuthenticationFilter.java` — Spring Security filter that reads `Authorization: Bearer <token>`, validates, and sets `SecurityContext`
2. Implement User Service:
   - `User` JPA entity mapping to `users` table
   - `UserRepository` extending `JpaRepository`
   - `AuthService` — register (BCrypt hash password, save user, generate JWT), login (verify credentials, generate JWT)
   - `AuthController` — `POST /register`, `POST /login`, `GET /me`, `PUT /me`
   - DTOs: `RegisterRequest`, `LoginRequest`, `LoginResponse`, `UserDto`
   - `SecurityConfig` — permit `/register` and `/login`, require auth for everything else
3. Add JWT validation to Budget Service and Transaction Service `SecurityConfig` (using common filter)

**Key Decisions:**
- JWT secret is a shared string in each service's `application.yml` (simple, sufficient for single-user app)
- Token expiry: 24 hours
- No refresh token mechanism (keep it simple)

**Verification:** `curl POST /register` returns JWT. `curl POST /login` returns JWT. `curl GET /me` with JWT header returns user info. Calling without JWT returns 401.

---

### Phase 3: Budget Service

**Goal:** Full budget category management — create categories, allocate income, transfer between categories, view balances.

**Tasks:**
1. JPA Entities:
   - `BudgetCategory` — maps to `budget_categories` table
   - `Allocation` — maps to `allocations` table
   - `CategoryTransfer` — maps to `category_transfers` table
2. Repositories: `CategoryRepository`, `AllocationRepository`, `TransferRepository`
3. Services:
   - `CategoryService` — CRUD operations, ownership validation (user can only access their own categories)
   - `AllocationService` — allocate amount to category (creates allocation record, increments `allocated_amount` on category)
   - `TransferService` — transfer between categories (creates transfer record, adjusts both categories' `allocated_amount`)
4. Controllers:
   - `CategoryController` — CRUD endpoints
   - `AllocationController` — `POST /categories/{id}/allocate`, `GET /allocations`
   - `TransferController` — `POST /transfers`
   - `BudgetSummaryController` — `GET /summary` (all categories with `remaining = allocated - spent`)
   - `InternalCategoryController` — `POST /internal/categories/{id}/deduct`, `POST /internal/categories/{id}/refund`
5. DTOs: `CategoryRequest`, `CategoryResponse`, `AllocationRequest`, `TransferRequest`, `BudgetSummaryResponse`, `DeductRequest`
6. All financial operations wrapped in `@Transactional`

**Key Decisions:**
- Transfer adjusts `allocated_amount` on both categories (from decreases, to increases)
- Deduct/refund adjusts `spent_amount` (called by Transaction Service)
- Category deletion only allowed when both `allocated_amount` and `spent_amount` are 0
- Internal endpoints have no JWT requirement but are not exposed through gateway

**Verification:** Create categories → allocate money → check summary shows correct balances → transfer between categories → verify both balances updated → call deduct endpoint → verify spent_amount increases.

---

### Phase 4: Transaction Service

**Goal:** Record income and expenses. Expenses automatically deduct from budget category balances via cross-service HTTP call.

**Tasks:**
1. JPA Entity:
   - `Transaction` — maps to `transactions` table
   - `TransactionType` enum — `INCOME`, `EXPENSE`
2. Repository: `TransactionRepository` with custom queries for filtering (by type, category, date range) and pagination
3. Cross-service client:
   - `BudgetServiceClient` — Spring `@Service` using `RestTemplate` or `WebClient`
   - Methods: `deduct(categoryId, amount)`, `refund(categoryId, amount)`
   - Base URL configured in `application.yml`: `budget.service.url=http://localhost:8082`
4. Service:
   - `TransactionService`:
     - `recordIncome(userId, amount, description, date)` — saves INCOME transaction (no budget interaction)
     - `recordExpense(userId, amount, categoryId, description, date)` — saves EXPENSE transaction AND calls `BudgetServiceClient.deduct()`
     - `deleteTransaction(id)` — if EXPENSE, calls `BudgetServiceClient.refund()` before deleting
     - `listTransactions(userId, filters, pagination)` — filtered list
     - `getMonthlySummary(userId, yearMonth)` — aggregate spending by category
5. Controllers:
   - `TransactionController` — income, expense, list, get, delete
   - `TransactionSummaryController` — monthly summary
6. DTOs: `IncomeRequest`, `ExpenseRequest`, `TransactionResponse`, `TransactionSummaryResponse`

**Key Decisions:**
- If Budget Service deduct call fails, the expense transaction is NOT saved (rollback)
- Income is just a record — allocation to categories is a separate user action in Budget Service
- Expenses require a `categoryId`; income does not

**Verification:** Record income → verify saved. Record expense → verify saved AND category `spent_amount` increased in Budget Service. Delete expense → verify category `spent_amount` decreased. List transactions with filters works.

---

### Phase 5: API Gateway

**Goal:** Single entry point for the frontend. All API calls go through port 8080.

**Tasks:**
1. Configure Spring Cloud Gateway routes in `application.yml`:
   - `/api/auth/**` → `http://localhost:8081`
   - `/api/budgets/**` → `http://localhost:8082`
   - `/api/transactions/**` → `http://localhost:8083`
2. Add global CORS configuration:
   - Allow origin: `http://localhost:5173`
   - Allow methods: GET, POST, PUT, DELETE, OPTIONS
   - Allow headers: Authorization, Content-Type
3. Optional: request logging filter for debugging

**Key Decisions:**
- JWT validation happens at each downstream service (not at gateway) — simpler and each service works independently
- Gateway is purely a router + CORS handler
- Internal endpoints (`/internal/**`) are NOT routed through the gateway

**Verification:** All previously working curl commands now work through `http://localhost:8080/api/...` instead of direct service ports. Frontend can make cross-origin requests without errors.

---

### Phase 6: Frontend

**Goal:** Fully functional UI for all features.

**Tasks:**
1. **Setup & Layout:**
   - Configure Tailwind CSS
   - Set up React Router with all routes
   - Build `AppLayout` with sidebar navigation (Dashboard, Categories, Allocate, Transactions, Transfer)
   - Build `TopBar` with user display name and logout button

2. **Authentication:**
   - `authStore` — token in localStorage, login/register/logout actions, Axios interceptor
   - `LoginPage` and `RegisterPage` with form validation
   - `ProtectedRoute` component — redirects to `/login` if no token

3. **Categories Management:**
   - `budgetStore` — categories state, CRUD actions
   - `CategoriesPage` — list of category cards with edit/delete
   - `CategoryForm` — modal or inline form for create/edit

4. **Income Allocation:**
   - `AllocatePage` — select category dropdown, enter dollar amount, submit
   - `AllocationHistory` — list of past allocations

5. **Transactions:**
   - `transactionStore` — transactions state, filters, add/delete actions
   - `TransactionsPage` — table with filters (type, category, date range)
   - `NewTransactionPage` — toggle between income/expense, category picker for expenses

6. **Transfers:**
   - `TransferPage` — from-category dropdown, to-category dropdown, amount input

7. **Dashboard:**
   - `DashboardPage` — fetches budget summary + transaction summary
   - `BudgetOverviewChart` — bar chart showing allocated vs spent per category (Recharts)
   - `SpendingSummaryCard` — total allocated, total spent, total remaining
   - `RecentTransactionsList` — last 5-10 transactions

**Verification:** Register → login → create categories → allocate income → record expenses → see balances update on dashboard → transfer money → verify all pages work end-to-end.

---

### Phase 7: Integration & Testing

**Goal:** Confidence that the entire system works correctly.

**Tasks:**
1. **Backend unit tests** (JUnit 5 + Mockito):
   - `AuthServiceTest` — register, login, duplicate email
   - `CategoryServiceTest` — CRUD, ownership validation
   - `AllocationServiceTest` — allocate, insufficient validation
   - `TransferServiceTest` — transfer, balance updates
   - `TransactionServiceTest` — income, expense with deduct, delete with refund
2. **Backend integration tests** (`@SpringBootTest` + H2 or Testcontainers):
   - Full controller tests with MockMvc
   - Cross-service communication test (Transaction → Budget deduct)
3. **Frontend component tests** (Vitest + React Testing Library):
   - Form submissions
   - Store actions with mocked API
4. **End-to-end manual test script:**
   - Register user
   - Create 4 categories: Housing, Food, Investment, Entertainment
   - Record $5000 income
   - Allocate: $2000 Housing, $800 Food, $1000 Investment, $500 Entertainment
   - Record expenses in each category
   - Overspend Food category
   - Transfer from Entertainment to Food
   - Verify dashboard shows correct totals
   - Delete a transaction, verify refund

**Verification:** All unit tests pass. Integration tests pass. Manual E2E test script completes successfully.

---

### Phase 8: Polish

**Goal:** Production-like quality and developer experience.

**Tasks:**
1. **Error handling:**
   - `@ControllerAdvice` + `@ExceptionHandler` in each service
   - Consistent error response format: `{ "error": "message", "status": 400 }`
   - Custom exceptions: `ResourceNotFoundException`, `InsufficientBalanceException`, `DuplicateCategoryException`
2. **Input validation:**
   - `@NotBlank`, `@Email`, `@Positive`, `@Size` annotations on all DTOs
   - Validation error responses with field-level messages
3. **Frontend polish:**
   - Loading spinners during API calls
   - Error alerts (toast notifications) for failed operations
   - Confirmation dialogs for delete operations
   - Consistent currency formatting (`$X,XXX.XX`)
   - Empty state messages ("No categories yet — create one!")
4. **Logging:**
   - SLF4J structured logging in all services
   - Request/response logging at controller level
5. **Documentation:**
   - `README.md` with setup instructions, prerequisites, how to run
6. **Optional:**
   - Dockerize all services with multi-stage Dockerfiles
   - Full `docker-compose.yml` that starts everything (DB + all services + frontend)

**Verification:** Invalid inputs return clear error messages. UI shows loading states. Delete actions require confirmation. README allows a new developer to run the app from scratch.

---

## 8. Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Balance storage | Denormalized on `budget_categories` | Avoids expensive joins; safe with `@Transactional` for single-user |
| Cross-service calls | Synchronous HTTP | Simple, sufficient for this scale. Saga/outbox pattern is overkill |
| JWT handling | Shared secret + common library | Each service validates independently; works without gateway |
| Service discovery | None (hardcoded URLs) | Practical for local dev and Docker Compose |
| Income vs allocation | Separate actions | Income is a record; allocation is a budget decision. Allows unallocated income |
| Overspend policy | Allowed (negative balance) | User transfers money to fix it. No blocking — better UX |
| Build tool | Gradle multi-project | Shared dependencies, common module support |
| Frontend state | Zustand | Lightweight, less boilerplate than Redux for a personal app |
