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
    Project = var.project_name
  })
}

resource "random_id" "suffix" {
  byte_length = 3
}

# -------------------------
# Network piece (Security Group)
# -------------------------
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Security group with restricted ingress"
  vpc_id      = data.aws_vpc.default.id

  # Restrict SSH to a single trusted IP (your public IP /32) via tfvars.
  ingress {
    description = "SSH restricted to trusted IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip_for_ssh]
  }

  # Allow all outbound traffic (common default)
  egress {
    description = "Egress restricted to internal VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  tags = local.common_tags
}

# -------------------------
# S3 piece (Bucket + security controls)
# -------------------------
resource "aws_s3_bucket" "log_bucket" {
  bucket = lower("${var.project_name}-logs-${random_id.suffix.hex}")
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "log_bucket_pab" {
  bucket = aws_s3_bucket.log_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_sse" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "log_bucket_versioning" {
  bucket = aws_s3_bucket.log_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = lower("${var.project_name}-${random_id.suffix.hex}")
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}




resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_sse" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {

      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
    }
  }
}


resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id

  versioning_configuration {
    status = "Enabled"
  }

}

# Enable S3 server access logging on the data bucket
resource "aws_s3_bucket_logging" "data_bucket_logging" {
  bucket        = aws_s3_bucket.data_bucket.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "access-logs/"
}

# -------------------------
# IAM (least privilege demo)

# -------------------------
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


# Scope GetObject to a specific key to avoid wildcard object access finding
resource "aws_iam_policy" "s3_read_only_bucket" {
  name        = "${var.project_name}-s3-readonly"
  description = "Read-only access scoped tightly to the project S3 bucket"



  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.data_bucket.arn
      },
      {

        Sid      = "ReadSpecificObject"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.data_bucket.arn}/allowed.txt"

      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "attach_s3_read_only" {
  role       = aws_iam_role.test_role.name
  policy_arn = aws_iam_policy.s3_read_only_bucket.arn
}