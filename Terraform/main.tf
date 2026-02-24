terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  common_tags = merge(var.tags, {
    NamePrefix = var.project_name
  })
}

# Unique suffix for bucket names (S3 bucket names must be globally unique)
resource "random_id" "suffix" {
  byte_length = 3
}

# -------------------------
# Network piece (Security Group)
# -------------------------
# Using default VPC keeps this simple and cheap.

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "open_sg" {
  name        = "${var.project_name}-open-sg"
  description = "Intentionally permissive SG for misconfiguration testing"
  vpc_id      = data.aws_vpc.default.id

  # Intentional misconfiguration:
  # Open inbound SSH to the world (easy for tfsec to detect).
  ingress {
    description = "SSH open to world (intentional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# -------------------------
# S3 piece (Bucket + public access settings)
# -------------------------
resource "aws_s3_bucket" "data_bucket" {
  bucket = lower("${var.project_name}-${random_id.suffix.hex}")
  tags   = local.common_tags
}

# Intentional misconfiguration:
# Disable "Block Public Access" (easy for tfsec to detect).
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# -------------------------
# IAM piece (Overly permissive policy)
# -------------------------
resource "aws_iam_policy" "over_permissive" {
  name        = "${var.project_name}-over-permissive"
  description = "Intentionally permissive policy for testing (do not use in production)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach the policy to a role (avoids creating user credentials).
resource "aws_iam_role" "test_role" {
  name = "${var.project_name}-test-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "attach_over_permissive" {
  role       = aws_iam_role.test_role.name
  policy_arn = aws_iam_policy.over_permissive.arn
}

## Test comment for the PR Gating