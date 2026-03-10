# Lens for E-Learning Backend

FastAPI backend service for Lens for E-Learning MVP.

## Setup

### 1. Create Virtual Environment

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### 3. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your configuration:
- AWS credentials and region
- Cognito User Pool details
- External API keys (YouTube, Google Search)
- JWT secret key

### 4. Download spaCy Model

```bash
python -m spacy download en_core_web_sm
```

### 5. Run Development Server

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API will be available at http://localhost:8000

API documentation: http://localhost:8000/docs

## Testing

### Run All Tests

```bash
pytest
```

### Run with Coverage

```bash
pytest --cov=app --cov-report=html
```

View coverage report: `open htmlcov/index.html`

### Run Specific Tests

```bash
# Unit tests only
pytest tests/test_*.py

# Property-based tests only
pytest tests/property_*.py

# Specific test file
pytest tests/test_health.py -v
```

## Code Quality

### Format Code

```bash
black app tests
isort app tests
```

### Lint Code

```bash
flake8 app tests
```

### Type Check

```bash
mypy app
```

## Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   ├── core/
│   │   ├── config.py        # Configuration
│   │   └── security.py      # Authentication utilities
│   ├── api/
│   │   └── v1/
│   │       ├── auth.py      # Auth endpoints
│   │       ├── scans.py     # Scan endpoints
│   │       └── bookmarks.py # Bookmark endpoints
│   ├── models/
│   │   └── schemas.py       # Pydantic models
│   ├── services/
│   │   ├── ocr.py          # OCR service
│   │   ├── nlp.py          # NLP service
│   │   └── search.py       # Search service
│   └── db/
│       └── dynamodb.py     # DynamoDB client
├── tests/
│   ├── conftest.py         # Test fixtures
│   ├── test_*.py           # Unit tests
│   └── property_*.py       # Property-based tests
├── requirements.txt
├── requirements-dev.txt
└── pyproject.toml
```

## API Endpoints

### Health Check
- `GET /api/v1/health` - Health check

### Authentication
- `POST /api/v1/auth/register` - Register new user
- `POST /api/v1/auth/login` - Login user
- `POST /api/v1/auth/logout` - Logout user
- `POST /api/v1/auth/refresh` - Refresh token
- `POST /api/v1/auth/verify-email` - Verify email
- `GET /api/v1/auth/me` - Get current user

### Scans
- `POST /api/v1/scans` - Create new scan
- `GET /api/v1/scans/{scan_id}` - Get scan details
- `GET /api/v1/scans` - List user scans
- `DELETE /api/v1/scans/{scan_id}` - Delete scan

### Bookmarks
- `POST /api/v1/scans/{scan_id}/bookmarks` - Bookmark resource
- `GET /api/v1/bookmarks` - Get all bookmarks
- `DELETE /api/v1/bookmarks/{bookmark_id}` - Remove bookmark
