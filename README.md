# Personal Finance Tracking App

A microservices-based personal finance application for allocating income into custom budget categories, tracking spending, and transferring money between categories.

## Tech Stack

- **Frontend:** React 18, TypeScript, Vite, Tailwind CSS, Zustand, Recharts
- **Backend:** Java 17, Spring Boot 3.3, Spring Cloud Gateway
- **Database:** PostgreSQL 16 (3 logical databases)
- **Infrastructure:** Docker Compose, Gradle multi-project

## Architecture

```
React SPA (5173) → API Gateway (8080) → User Service (8081)
                                       → Budget Service (8082)
                                       → Transaction Service (8083)
                                              ↓
                                        PostgreSQL 16
                                   (user_db, budget_db, transaction_db)
```

## Prerequisites

- Java 17+
- Node.js 18+
- Docker & Docker Compose

## Getting Started

### 1. Start the database

```bash
docker-compose up -d
```

### 2. Build and run backend services

```bash
cd backend
./gradlew build -x test

# Run each service in a separate terminal:
./gradlew :api-gateway:bootRun
./gradlew :user-service:bootRun
./gradlew :budget-service:bootRun
./gradlew :transaction-service:bootRun
```

### 3. Start the frontend

```bash
cd frontend
npm install
npm run dev
```

The app will be available at `http://localhost:5173`.

## Project Structure

```
personal_finance_app/
├── docker-compose.yml
├── init-databases.sql
├── backend/
│   ├── common/                  # Shared JWT library & auth filter
│   ├── api-gateway/             # Spring Cloud Gateway (port 8080)
│   ├── user-service/            # Auth & user management (port 8081)
│   ├── budget-service/          # Categories, allocations, transfers (port 8082)
│   └── transaction-service/     # Income & expense tracking (port 8083)
└── frontend/                    # React SPA
    └── src/
        ├── api/
        ├── stores/
        ├── pages/
        ├── components/
        ├── types/
        └── utils/
```

## API Overview

| Service      | Base Path             | Port |
|--------------|-----------------------|------|
| Auth         | `/api/auth`           | 8081 |
| Budgets      | `/api/budgets`        | 8082 |
| Transactions | `/api/transactions`   | 8083 |
| Gateway      | `/api/*`              | 8080 |
