terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

# This enables S3 server-side encryption for Terraform state writes. 
# In a production environment, also verify the bucket's encryption configuration and access controls.
  backend "s3" {
    bucket  = "acme-health-terraform-state"
    key     = "platform/prod.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "clinical-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "site_distribution_arn" {
  type        = string
  description = "ARN of the CloudFront distribution that serves the marketing website."
}


# SECURITY FIX:
# The deployment pipeline must provide the exact immutable ECR image tag.
# Use the Git commit SHA so each release can be traced to its source code.

variable "image_tag" {
  description = "Immutable ECR image tag, preferably the Git commit SHA."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.image_tag) > 0 && var.image_tag != "latest"
    error_message = "image_tag must be a non-empty version tag and cannot be latest."
  }
}


# SECURITY FIX:
# Only the explicitly configured GitHub repository and branch should
# be allowed to assume the AWS deployment role through GitHub OIDC.
# Do not use wildcard repository or branch names.

variable "github_repository" {
  description = "Exact GitHub repository in OWNER/REPO format."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.github_repository) > 0 && !strcontains(var.github_repository, "*")
    error_message = "Provide an exact OWNER/REPO name without wildcards."
  }
}

variable "github_branch" {
  description = "Branch permitted to assume the AWS deployment role."
  type        = string
  default     = "main"

  validation {
    condition     = length(var.github_branch) > 0 && !strcontains(var.github_branch, "*")
    error_message = "Provide an exact branch name without wildcards."
  }
}


# SECURITY FIX:
# Reference an existing Secrets Manager secret instead of placing the
# database password directly in the ECS container environment.
# Supply the secret ARN through your approved deployment process.
# Do not create the secret value in Terraform configuration.
variable "db_password_secret_arn" {
  description = "ARN of the existing Secrets Manager secret containing the DB password."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.db_password_secret_arn))
    error_message = "Provide a valid Secrets Manager secret ARN."
  }
}


variable "final_snapshot_suffix" {
  description = "Unique suffix for the RDS final snapshot identifier."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.final_snapshot_suffix) > 0 && can(regex("^[a-zA-Z0-9-]+$", var.final_snapshot_suffix))
    error_message = "Use a non-empty suffix containing only letters, numbers, and hyphens."
  }
}


# SECURITY NOTE:
# This variable has no hardcoded default to prevent accidental credential exposure.
# The deployment pipeline must retrieve the password from AWS Secrets Manager
# or another approved secret store and supply it securely at deployment time.
# Do not commit passwords to Git, Terraform variable files, or pipeline logs.
variable "db_password" {
  description = "Database password supplied securely at deployment time."
  type        = string
  sensitive   = true
  nullable    = false
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

# Partner organizations upload clinical documents here (PDFs, CSV extracts,
# FHIR bundles). Each partner writes under its own prefix: incoming/<partner_id>/
resource "aws_s3_bucket" "raw_landing" {
  bucket = "acme-health-raw-landing"
}

# It granted access to Principal = "*" and relied on IP address conditions,
# rather than explicitly identifying and authorizing approved partner identities.
#
# IMPACT:
# Removing this policy also removes the existing partner-access configuration.
# This is intentional for this security-remediation baseline to prevent
# unintended access to sensitive clinical documents.
#
# FOLLOW-UP REQUIRED:
# Configure partner uploads separately using approved, least-privilege IAM
# roles or presigned URLs, scoped to each partner's own incoming/<partner_id>/
# prefix. Grant only the S3 actions each partner requires.
# Do not reintroduce a wildcard principal or broad bucket permissions.

resource "aws_s3_bucket_public_access_block" "raw_landing" {
  bucket                  = aws_s3_bucket.raw_landing.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}


# Logos and public PDFs for the marketing website, served through CloudFront.
resource "aws_s3_bucket" "public_assets" {
  bucket = "acme-health-public-assets"
}

resource "aws_s3_bucket_public_access_block" "public_assets" {
  bucket                  = aws_s3_bucket.public_assets.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "public_assets" {
  bucket = aws_s3_bucket.public_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.public_assets.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = var.site_distribution_arn }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Audit logging
# -----------------------------------------------------------------------------

# SECURITY FIX:
# Audit logs are critical evidence for security investigations and compliance.
# Prevent Terraform from emptying the bucket as part of bucket destruction.
# Review retention, access controls, and recovery requirements before rollout.

resource "aws_s3_bucket" "audit_logs" {
  bucket        = "acme-health-audit-logs"
  force_destroy = false
}

resource "aws_s3_bucket_policy" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.audit_logs.arn
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit_logs.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# SECURITY FIX:
# Capture management events across AWS regions to improve detection coverage.
# Enable log-file validation to help detect modification or deletion of logs.
# Confirm the trail's event selectors and delivery configuration during review.

resource "aws_cloudtrail" "main" {
  name                          = "acme-trail"
  s3_bucket_name                = aws_s3_bucket.audit_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.audit_logs]
}

# -----------------------------------------------------------------------------
# Container platform
# -----------------------------------------------------------------------------

# SECURITY FIX:
# Scan container images for known vulnerabilities when they are pushed.
# Immutable tags prevent an existing version tag from being overwritten.
#
# DEPLOYMENT NOTE:
# Build and push a new image with a unique tag for each release.
# Review scan findings and define a remediation process for critical findings.

resource "aws_ecr_repository" "document_parser" {
  name                 = "document-parser"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "acme-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# SECURITY FIX:
# ECS retrieves the database password using its execution role.
# Limit secret access to the one explicitly configured secret ARN.
# NOTE: If the secret uses a customer-managed KMS key, the execution role may also need narrowly scoped kms:Decrypt permission for that key.

resource "aws_iam_role_policy" "task_execution_secret" {
  name = "read-database-password"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.db_password_secret_arn
      }
    ]
  })
}


resource "aws_iam_role" "pipeline_task" {
  name               = "acme-pipeline-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}


# SECURITY FIX:
# Apply least privilege to the ECS document parser task role.
# The parser can list and read only documents in the incoming/ prefix.
# It cannot administer S3, access arbitrary secrets, or launch arbitrary tasks.
#
# PRODUCTION NOTE:
# Add secret access or ECS task-launch permissions only after confirming
# the exact secret ARN, task definition ARN, and required IAM role ARNs.
# Do not restore wildcard permissions to work around an access error.

resource "aws_iam_role_policy" "pipeline_task" {
  name = "pipeline-permissions"
  role = aws_iam_role.pipeline_task.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid      = "ListIncomingDocuments"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.raw_landing.arn

        Condition = {
          StringLike = {
            "s3:prefix" = [
              "incoming",
              "incoming/*"
            ]
          }
        }
      },
      {
        Sid      = "ReadIncomingDocuments"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.raw_landing.arn}/incoming/*"
      }
    ]
  })
}


resource "aws_cloudwatch_log_group" "document_parser" {
  name = "/ecs/document-parser"
}

# Parses and OCRs every document partners upload, then loads the results into
# the clinical database.
resource "aws_ecs_task_definition" "document_parser" {
  family                   = "document-parser"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 4096
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.pipeline_task.arn

  container_definitions = jsonencode([
    {
      name      = "parser"
      image     = "${aws_ecr_repository.document_parser.repository_url}:${var.image_tag}"
      essential = true
     environment = [
        { name = "DB_HOST", value = aws_db_instance.clinical.address },
        { name = "DB_USER", value = "acme_admin" },
        { name = "LOG_LEVEL", value = "INFO" }
      ]

      # ECS retrieves this secret at task startup.
      # The password is no longer declared as a plaintext environment value
      # in the task definition configuration.
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = var.db_password_secret_arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.document_parser.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "parser"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

resource "aws_security_group" "pipeline" {
  name        = "acme-pipeline-tasks"
  description = "ECS pipeline tasks"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SECURITY FIX:
# PostgreSQL must not accept connections from every IPv4 address.
# Permit database connections only from ECS pipeline tasks.
# Before applying in production, verify all legitimate DB clients
# and migrate any undocumented consumers to an approved security group.

resource "aws_security_group" "db" {
  name        = "acme-clinical-db"
  description = "Clinical database"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from ECS pipeline tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.pipeline.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "clinical" {
  name       = "acme-clinical-db"
  # RDS should use private subnets across at least two Availability Zones.
  # Verify the supplied subnet IDs are genuinely private before rollout.
  subnet_ids = var.private_subnet_ids
}


# SECURITY FIX:
# Keep the clinical database private, encrypt storage, enable backups,
# and protect against accidental deletion.
#
# ROLLOUT NOTE:
# Confirm backup retention requirements, encryption/KMS requirements,
# maintenance windows, and restore procedures before production rollout.
# A final snapshot is required when Terraform destroys this instance.

resource "aws_db_instance" "clinical" {
  identifier             = "acme-clinical-prod"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.m6g.large"
  allocated_storage      = 200
  username               = "acme_admin"
  manage_master_user_password = true    # Let RDS generate and manage the master password in Secrets Manager.This avoids passing the database password through Terraform variables.
  db_subnet_group_name   = aws_db_subnet_group.clinical.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible     = false
  storage_encrypted       = true
  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "acme-clinical-prod-final-${var.final_snapshot_suffix}"
# Supply a unique value when running Terraform, for example: terraform plan -var="final_snapshot_suffix=20261029"

  # Avoid accidental immediate changes during a production rollout.
  apply_immediately = false
}


# -----------------------------------------------------------------------------
# CI/CD
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}


# SECURITY FIX:
# Restrict role assumption to one repository and one branch.
# GitHub OIDC avoids the need for long-lived AWS access keys.
resource "aws_iam_role" "github_deploy" {
  name = "acme-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

            # Exact repository and branch; no wildcard access.
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
          }
        }
      }
    ]
  })
}
# Removed AdministratorAccess from the GitHub deployment role

# Legacy CI user. Kept until the last two pipelines move to the OIDC role above.


# SECURITY FIX:
# Do not create or manage new long-lived IAM access keys for CI/CD.
# The legacy ci-deployer IAM user, AdministratorAccess attachment,
# access key resource, and credential outputs have been removed.
#
# ROLLOUT REQUIREMENT:
# Before applying this change in a real AWS account:
# 1. Identify every pipeline still using ci-deployer.
# 2. Migrate and test those pipelines using GitHub OIDC.
# 3. Grant the OIDC role only the deployment permissions it requires.
# 4. Revoke existing ci-deployer access keys and remove its
#    AdministratorAccess attachment.
# 5. Decommission the IAM user after confirming no consumers remain.
#
# Do not output, commit, or log access-key secrets.

