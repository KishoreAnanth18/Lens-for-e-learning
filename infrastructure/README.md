# Infrastructure Setup

This directory contains Terraform configuration for AWS infrastructure setup.

## Prerequisites

1. AWS Account (Free Tier eligible)
2. AWS CLI installed and configured
3. Terraform installed (>= 1.0)

## Setup Instructions

### 1. Configure AWS Credentials

```bash
aws configure
```

Enter your AWS Access Key ID, Secret Access Key, and default region (us-east-1).

### 2. Initialize Terraform

```bash
cd infrastructure/terraform
terraform init
```

### 3. Review Infrastructure Plan

```bash
terraform plan
```

### 4. Apply Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to create the resources.

### 5. Save Outputs

After successful deployment, save the outputs:

```bash
terraform output > ../../backend/.terraform-outputs
```

## Resources Created

- **DynamoDB Table**: `lens-elearning-prod` with single-table design
- **S3 Bucket**: `lens-elearning-images` with lifecycle policies
- **Cognito User Pool**: For user authentication
- **IAM Roles**: For Lambda execution with necessary permissions

## Free Tier Compliance

All resources are configured to stay within AWS Free Tier limits:
- DynamoDB: On-demand billing (25GB storage, 25 RCU/WCU)
- S3: Standard storage (5GB)
- Cognito: Up to 50,000 MAUs
- Lambda: 1M requests/month, 400,000 GB-seconds compute

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all data. Make sure to backup any important data before destroying.
