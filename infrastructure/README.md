# Infrastructure Setup

Terraform configuration for AWS infrastructure.

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.0

## Deploy

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

Save outputs for backend configuration:

```bash
terraform output -json > ../../terraform-outputs.json
```

## Resources Created

| Resource | Name |
|----------|------|
| DynamoDB Table | `lens-elearning-prod` |
| S3 Bucket | `lens-elearning-images` |
| Cognito User Pool | `lens-elearning-users` |
| IAM Role | Lambda execution role |

## Estimated Costs

For light dev/testing (few requests per day):

| Service | Cost/month |
|---------|-----------|
| DynamoDB | ~$0.01-0.05 |
| S3 | ~$0.01-0.02 |
| Lambda | ~$0.01-0.05 |
| Cognito | $0.00 (first 50K users free) |
| **Total** | **~$0.03-0.12** |

Set up billing alerts at $1, $5, $10 thresholds in AWS Billing → Budgets.

## Destroy (avoid ongoing charges)

```bash
terraform destroy
```

> Warning: this permanently deletes all data. Back up first.

## Local Development (No AWS)

Use LocalStack instead — see [LOCAL-DEVELOPMENT.md](../LOCAL-DEVELOPMENT.md).
