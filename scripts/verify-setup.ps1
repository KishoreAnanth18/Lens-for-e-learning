# Lens for E-Learning Setup Verification Script (PowerShell)

Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Lens for E-Learning Setup Verification" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

function Check-Command {
    param($CommandName)
    if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
        Write-Host "✓ $CommandName is installed" -ForegroundColor Green
        return $true
    } else {
        Write-Host "✗ $CommandName is not installed" -ForegroundColor Red
        return $false
    }
}

function Check-PythonVersion {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $version = python --version 2>&1 | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
        $parts = $version.Split('.')
        if ([int]$parts[0] -ge 3 -and [int]$parts[1] -ge 11) {
            Write-Host "✓ Python $version (>= 3.11)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠ Python $version (3.11+ recommended)" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "✗ Python is not installed" -ForegroundColor Red
        return $false
    }
}

function Check-FlutterVersion {
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        $version = flutter --version 2>&1 | Select-String -Pattern "Flutter (\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
        Write-Host "✓ Flutter $version" -ForegroundColor Green
        return $true
    } else {
        Write-Host "✗ Flutter is not installed" -ForegroundColor Red
        return $false
    }
}

function Check-AWSCredentials {
    try {
        $account = aws sts get-caller-identity --query Account --output text 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ AWS credentials configured (Account: $account)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ AWS credentials not configured" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ AWS credentials not configured" -ForegroundColor Red
        return $false
    }
}

function Check-File {
    param($FilePath)
    if (Test-Path $FilePath -PathType Leaf) {
        Write-Host "✓ $FilePath exists" -ForegroundColor Green
        return $true
    } else {
        Write-Host "✗ $FilePath not found" -ForegroundColor Red
        return $false
    }
}

function Check-Directory {
    param($DirPath)
    if (Test-Path $DirPath -PathType Container) {
        Write-Host "✓ $DirPath exists" -ForegroundColor Green
        return $true
    } else {
        Write-Host "✗ $DirPath not found" -ForegroundColor Red
        return $false
    }
}

# Run checks
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
Write-Host ""

Check-Command python
Check-PythonVersion
Check-Command pip
Check-Command flutter
Check-FlutterVersion
Check-Command terraform
Check-Command aws
Check-Command git
Write-Host ""

Write-Host "Checking AWS configuration..." -ForegroundColor Cyan
Write-Host ""
Check-AWSCredentials
Write-Host ""

Write-Host "Checking project structure..." -ForegroundColor Cyan
Write-Host ""
Check-Directory "backend"
Check-Directory "backend\app"
Check-Directory "backend\tests"
Check-File "backend\requirements.txt"
Check-File "backend\.env.example"
Write-Host ""

Check-Directory "mobile"
Check-Directory "mobile\lib"
Check-Directory "mobile\test"
Check-File "mobile\pubspec.yaml"
Write-Host ""

Check-Directory "infrastructure"
Check-Directory "infrastructure\terraform"
Check-File "infrastructure\terraform\main.tf"
Write-Host ""

Check-Directory ".github"
Check-Directory ".github\workflows"
Check-File ".github\workflows\backend-ci.yml"
Check-File ".github\workflows\mobile-ci.yml"
Write-Host ""

Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Verification Complete" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Deploy infrastructure: cd infrastructure\terraform; terraform apply"
Write-Host "2. Set up backend: cd backend; pip install -r requirements.txt"
Write-Host "3. Set up mobile: cd mobile; flutter pub get"
Write-Host "4. Review SETUP.md for detailed instructions"
