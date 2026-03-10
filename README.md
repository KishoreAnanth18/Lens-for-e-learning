# Lens for E-Learning MVP

A mobile application that transforms physical textbook content into curated digital learning resources using OCR, NLP, and intelligent search.

## Project Structure

```
lens-elearning-mvp/
├── backend/              # FastAPI backend service
│   ├── app/             # Application code
│   ├── tests/           # Unit and property tests
│   └── requirements.txt # Python dependencies
├── mobile/              # Flutter mobile app
│   ├── lib/            # Application code
│   ├── test/           # Widget and unit tests
│   └── pubspec.yaml    # Flutter dependencies
├── infrastructure/      # AWS infrastructure (Terraform)
│   └── terraform/      # Terraform configuration
└── .github/            # CI/CD workflows
    └── workflows/      # GitHub Actions
```

## Architecture

- **Mobile App**: Flutter (iOS/Android)
- **Backend API**: FastAPI on AWS Lambda
- **Storage**: AWS S3 (images), DynamoDB (data)
- **Authentication**: AWS Cognito
- **OCR**: Tesseract
- **NLP**: spaCy with RAKE keyword extraction
- **Search**: YouTube Data API, Google Custom Search API

## Quick Start

### Prerequisites

- Python 3.11+
- Flutter 3.0+
- AWS Account (Free Tier)
- Terraform 1.0+
- Node.js 18+ (for some tools)

### 1. Infrastructure Setup

```bash
cd infrastructure/terraform
terraform init
terraform apply
```

Save the outputs to configure backend and mobile app.

### 2. Backend Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Copy and configure environment variables
cp .env.example .env
# Edit .env with your AWS credentials and API keys

# Run tests
pytest

# Start development server
uvicorn app.main:app --reload
```

### 3. Mobile App Setup

```bash
cd mobile
flutter pub get

# Run tests
flutter test

# Run on device/emulator
flutter run
```

## Development Workflow

### Backend Development

1. Create feature branch from `develop`
2. Write tests first (TDD approach)
3. Implement functionality
4. Run linting: `black app tests && isort app tests && flake8 app tests`
5. Run tests: `pytest --cov=app`
6. Create pull request

### Mobile Development

1. Create feature branch from `develop`
2. Write widget/unit tests
3. Implement UI and logic
4. Run formatting: `dart format .`
5. Run analysis: `flutter analyze`
6. Run tests: `flutter test`
7. Create pull request

## Testing

### Backend Testing

```bash
# Unit tests
pytest tests/

# Property-based tests
pytest tests/ -k property

# Coverage report
pytest --cov=app --cov-report=html
```

### Mobile Testing

```bash
# Unit tests
flutter test

# Widget tests
flutter test test/widget_test.dart

# Coverage
flutter test --coverage
```

## Deployment

### Backend Deployment

Lambda functions are deployed using AWS SAM or Serverless Framework (to be configured in later tasks).

### Mobile Deployment

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## Free Tier Compliance

The system is designed to operate within AWS Free Tier limits:

- **Lambda**: 1M requests/month, 400,000 GB-seconds
- **DynamoDB**: 25GB storage, 25 RCU/WCU
- **S3**: 5GB storage, 20,000 GET requests, 2,000 PUT requests
- **Cognito**: 50,000 MAUs
- **API Gateway**: 1M API calls/month

Monitor usage in AWS Console to ensure compliance.

## Documentation

- [Requirements](.kiro/specs/lens-elearning-mvp/requirements.md)
- [Design](.kiro/specs/lens-elearning-mvp/design.md)
- [Tasks](.kiro/specs/lens-elearning-mvp/tasks.md)
- [Infrastructure Setup](infrastructure/README.md)

## License

MIT License - See LICENSE file for details
