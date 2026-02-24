variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-2"], var.region)
    error_message = "region must be one of: us-east-1, us-east-2, us-west-2."
  }
}

variable "project_name" {
  description = "Prefix used to name resources"
  type        = string
  default     = "secure-terraform-pipeline"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 32
    error_message = "project_name must be between 3 and 32 characters."
  }
}

# Keep this if you want to use it later for your "secure" scenario.
# It is not currently used in main.tf (your SG is intentionally open for tfsec testing).
variable "allowed_ip_for_ssh" {
  description = "Optional: Your public IP in CIDR form for safer SSH examples (e.g., 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)

  default = {
    Owner       = "Jeremiah"
    Project     = "secure-terraform-pipeline"
    Environment = "dev"
  }

  validation {
    condition = alltrue([
      contains(keys(var.tags), "Owner"),
      contains(keys(var.tags), "Project"),
      contains(keys(var.tags), "Environment")
    ])
    error_message = "tags must include Owner, Project, and Environment."
  }
}