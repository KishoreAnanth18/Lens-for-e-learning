# Backend

FastAPI backend for Lens for E-Learning MVP.

## Setup

```bash
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

Configure environment:

```bash
cp .env.example .env
# Edit .env with your values
```

For local development with LocalStack, see [LOCAL-DEVELOPMENT.md](../LOCAL-DEVELOPMENT.md).

## Run

```bash
uvicorn app.main:app --reload
```

API docs: http://localhost:8000/docs
Health check: http://localhost:8000/api/v1/health
AWS connectivity: http://localhost:8000/api/v1/health/aws

## Test

```bash
pytest
pytest --cov=app --cov-report=html
```

## Lint & Format

```bash
black app tests
isort app tests
flake8 app tests
mypy app
```

## API Endpoints (planned)

### Auth
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/logout`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/verify-email`
- `GET  /api/v1/auth/me`

### Scans
- `POST   /api/v1/scans`
- `GET    /api/v1/scans/{scan_id}`
- `GET    /api/v1/scans`
- `DELETE /api/v1/scans/{scan_id}`

### Bookmarks
- `POST   /api/v1/scans/{scan_id}/bookmarks`
- `GET    /api/v1/bookmarks`
- `DELETE /api/v1/bookmarks/{bookmark_id}`
