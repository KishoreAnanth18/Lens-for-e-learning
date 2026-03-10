# Lens for E-Learning - Complete Setup Guide

This guide walks you through setting up the complete Lens for E-Learning MVP development environment.

## Prerequisites Checklist

- [ ] AWS Account (Free Tier eligible)
- [ ] Python 3.11 or higher
- [ ] Flutter SDK 3.0 or higher
- [ ] Terraform 1.0 or higher
- [ ] Git
- [ ] Code editor (VS Code recommended)

## Step 1: Clone Repository

```bash
git clone <repository-url>
cd lens-elearning-mvp
```

## Step 2: AWS Infrastructure Setup

### 2.1 Configure AWS CLI

```bash
aws configure
```

Enter:
- AWS Access Key ID
- AWS Secret Access Key
- Default region: `us-east-1`
- Default output format: `json`

### 2.2 Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted.

### 2.3 Save Terraform Outputs

```bash
terraform output -json > ../../terraform-outputs.json
```

## Step 3: Backend Setup

### 3.1 Create Virtual Environment

```bash
cd ../../backend
python -m venv venv

# On macOS/Linux:
source venv/bin/activate

# On Windows:
venv\Scripts\activate
```

### 3.2 Install Dependencies

```bash
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### 3.3 Download spaCy Model

```bash
python -m spacy download en_core_web_sm
```

### 3.4 Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and fill in values from Terraform outputs:
- `AWS_ACCOUNT_ID`: Your AWS account ID
- `COGNITO_USER_POOL_ID`: From terraform output
- `COGNITO_CLIENT_ID`: From terraform output
- `COGNITO_CLIENT_SECRET`: From Cognito console
- `YOUTUBE_API_KEY`: From Google Cloud Console
- `GOOGLE_SEARCH_API_KEY`: From Google Cloud Console
- `GOOGLE_SEARCH_ENGINE_ID`: From Google Custom Search
- `JWT_SECRET_KEY`: Generate a secure random string

### 3.5 Run Tests

```bash
pytest
```

### 3.6 Start Development Server

```bash
uvicorn app.main:app --reload
```

Visit http://localhost:8000/docs to see API documentation.

## Step 4: Mobile App Setup

### 4.1 Install Flutter Dependencies

```bash
cd ../mobile
flutter pub get
```

### 4.2 Configure App

Create `lib/config/app_config.dart`:

```dart
class AppConfig {
  static const String apiBaseUrl = 'http://localhost:8000/api/v1';
  static const String cognitoUserPoolId = 'YOUR_USER_POOL_ID';
  static const String cognitoClientId = 'YOUR_CLIENT_ID';
  static const String awsRegion = 'us-east-1';
}
```

### 4.3 Run Tests

```bash
flutter test
```

### 4.4 Run App

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device-id>
```

## Step 5: External API Setup

### 5.1 YouTube Data API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable YouTube Data API v3
4. Create API credentials (API Key)
5. Add key to backend `.env` as `YOUTUBE_API_KEY`

### 5.2 Google Custom Search API

1. In Google Cloud Console, enable Custom Search API
2. Create API credentials (API Key)
3. Go to [Programmable Search Engine](https://programmablesearchengine.google.com/)
4. Create a new search engine
5. Get Search Engine ID
6. Add to backend `.env`:
   - `GOOGLE_SEARCH_API_KEY`
   - `GOOGLE_SEARCH_ENGINE_ID`

## Step 6: Verify Setup

### 6.1 Backend Health Check

```bash
curl http://localhost:8000/api/v1/health
```

Expected response:
```json
{
  "status": "healthy",
  "environment": "development",
  "version": "0.1.0"
}
```

### 6.2 Run All Tests

Backend:
```bash
cd backend
pytest --cov=app
```

Mobile:
```bash
cd mobile
flutter test
```

### 6.3 Check CI/CD

Push to GitHub and verify workflows run successfully:
- Backend CI
- Mobile CI
- Infrastructure CI

## Step 7: Development Workflow

### Backend Development

1. Activate virtual environment: `source venv/bin/activate`
2. Start server: `uvicorn app.main:app --reload`
3. Make changes
4. Run tests: `pytest`
5. Format code: `black app tests && isort app tests`
6. Commit and push

### Mobile Development

1. Start emulator or connect device
2. Run app: `flutter run`
3. Make changes (hot reload with `r`)
4. Run tests: `flutter test`
5. Format code: `dart format .`
6. Commit and push

## Troubleshooting

### Backend Issues

**Import errors**: Make sure virtual environment is activated
```bash
source venv/bin/activate  # or venv\Scripts\activate on Windows
```

**AWS credentials error**: Verify AWS CLI configuration
```bash
aws sts get-caller-identity
```

**spaCy model not found**: Download the model
```bash
python -m spacy download en_core_web_sm
```

### Mobile Issues

**Flutter not found**: Add Flutter to PATH
```bash
export PATH="$PATH:`pwd`/flutter/bin"
```

**Dependencies error**: Clean and reinstall
```bash
flutter clean
flutter pub get
```

**Build errors**: Update Flutter
```bash
flutter upgrade
```

### Infrastructure Issues

**Terraform state locked**: Force unlock (use carefully)
```bash
terraform force-unlock <lock-id>
```

**Resource already exists**: Import existing resource
```bash
terraform import aws_s3_bucket.images lens-elearning-images
```

## Next Steps

1. Review [Requirements](.kiro/specs/lens-elearning-mvp/requirements.md)
2. Review [Design](.kiro/specs/lens-elearning-mvp/design.md)
3. Start implementing [Tasks](.kiro/specs/lens-elearning-mvp/tasks.md)
4. Begin with Task 2: Authentication Service

## Support

For issues or questions:
1. Check documentation in `docs/` directory
2. Review GitHub Issues
3. Contact development team

## Free Tier Monitoring

Monitor AWS usage to stay within free tier:
- AWS Console → Billing → Free Tier Usage
- Set up billing alerts for $1, $5, $10 thresholds
- Review CloudWatch metrics regularly
