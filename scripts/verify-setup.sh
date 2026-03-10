#!/bin/bash

# Lens for E-Learning Setup Verification Script

echo "==================================="
echo "Lens for E-Learning Setup Verification"
echo "==================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check functions
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        return 1
    fi
}

check_python_version() {
    if command -v python3 &> /dev/null; then
        version=$(python3 --version | cut -d' ' -f2)
        major=$(echo $version | cut -d'.' -f1)
        minor=$(echo $version | cut -d'.' -f2)
        if [ $major -ge 3 ] && [ $minor -ge 11 ]; then
            echo -e "${GREEN}✓${NC} Python $version (>= 3.11)"
            return 0
        else
            echo -e "${YELLOW}⚠${NC} Python $version (3.11+ recommended)"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} Python 3 is not installed"
        return 1
    fi
}

check_flutter_version() {
    if command -v flutter &> /dev/null; then
        version=$(flutter --version | head -n1 | cut -d' ' -f2)
        echo -e "${GREEN}✓${NC} Flutter $version"
        return 0
    else
        echo -e "${RED}✗${NC} Flutter is not installed"
        return 1
    fi
}

check_aws_credentials() {
    if aws sts get-caller-identity &> /dev/null; then
        account=$(aws sts get-caller-identity --query Account --output text)
        echo -e "${GREEN}✓${NC} AWS credentials configured (Account: $account)"
        return 0
    else
        echo -e "${RED}✗${NC} AWS credentials not configured"
        return 1
    fi
}

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 exists"
        return 0
    else
        echo -e "${RED}✗${NC} $1 not found"
        return 1
    fi
}

check_directory() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 exists"
        return 0
    else
        echo -e "${RED}✗${NC} $1 not found"
        return 1
    fi
}

# Run checks
echo "Checking prerequisites..."
echo ""

check_command python3
check_python_version
check_command pip3
check_command flutter
check_flutter_version
check_command terraform
check_command aws
check_command git
echo ""

echo "Checking AWS configuration..."
echo ""
check_aws_credentials
echo ""

echo "Checking project structure..."
echo ""
check_directory "backend"
check_directory "backend/app"
check_directory "backend/tests"
check_file "backend/requirements.txt"
check_file "backend/.env.example"
echo ""

check_directory "mobile"
check_directory "mobile/lib"
check_directory "mobile/test"
check_file "mobile/pubspec.yaml"
echo ""

check_directory "infrastructure"
check_directory "infrastructure/terraform"
check_file "infrastructure/terraform/main.tf"
echo ""

check_directory ".github"
check_directory ".github/workflows"
check_file ".github/workflows/backend-ci.yml"
check_file ".github/workflows/mobile-ci.yml"
echo ""

echo "==================================="
echo "Verification Complete"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Deploy infrastructure: cd infrastructure/terraform && terraform apply"
echo "2. Set up backend: cd backend && pip install -r requirements.txt"
echo "3. Set up mobile: cd mobile && flutter pub get"
echo "4. Review SETUP.md for detailed instructions"
