# Lens for E-Learning MVP

A mobile application that transforms physical textbook content into curated digital learning resources using OCR, NLP, and intelligent search.

## Architecture

- **Mobile App**: Flutter (iOS/Android)
- **Backend API**: FastAPI on AWS Lambda
- **Storage**: AWS S3 (images), DynamoDB (data)
- **Authentication**: AWS Cognito
- **OCR**: Tesseract
- **NLP**: spaCy with RAKE keyword extraction
- **Search**: YouTube Data API, Google Custom Search API

## Project Structure

```
lens-elearning-mvp/
├── backend/              # FastAPI backend service
├── mobile/               # Flutter mobile app
├── infrastructure/       # AWS infrastructure (Terraform)
├── scripts/              # Local dev and utility scripts
└── .github/              # CI/CD workflows
```

## Quick Start (Local Development)

The recommended path uses LocalStack — no AWS account or costs needed.

```bash
# 1. Start LocalStack (S3, DynamoDB, Cognito)
docker compose up -d

# 2. Configure backend
cd backend
cp .env.example .env
# Set USE_LOCALSTACK=True in .env

# 3. Fetch Cognito IDs into .env
.\scripts\get-localstack-ids.ps1

# 4. Install dependencies and start
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

See [LOCAL-DEVELOPMENT.md](LOCAL-DEVELOPMENT.md) for the full guide.

## AWS Deployment

For integration testing or production, deploy with Terraform:

```bash
cd infrastructure/terraform
terraform init
terraform apply
```

See [infrastructure/README.md](infrastructure/README.md) for costs and setup details.

## Backend Development

```bash
cd backend
venv\Scripts\activate

# Run tests
pytest

# Run with coverage
pytest --cov=app

# Lint and format
black app tests && isort app tests && flake8 app tests
```

## Mobile Development

```bash
cd mobile
flutter pub get
flutter test
flutter run
```

## Free Tier Limits (AWS)

| Service | Free Tier |
|---------|-----------|
| Lambda | 1M requests/month |
| DynamoDB | 25GB storage |
| S3 | 5GB storage |
| Cognito | 50,000 MAUs |
| API Gateway | 1M calls/month |

## Spec & Tasks

- [Requirements](.kiro/specs/lens-elearning-mvp/requirements.md)
- [Design](.kiro/specs/lens-elearning-mvp/design.md)
- [Tasks](.kiro/specs/lens-elearning-mvp/tasks.md)
