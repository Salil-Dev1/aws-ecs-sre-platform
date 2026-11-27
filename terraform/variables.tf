variable "project_name" {
  description = "Short project name used for resource names and tags."
  type        = string
  default     = "taskflow"
}

variable "aws_region" {
  description = "AWS deployment region; defaults to the locally configured AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "atlas_project_id" {
  description = "MongoDB Atlas project that will host the TaskFlow M0 cluster."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in owner/repo form, trusted for deployments from main."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must have the form owner/repository."
  }
}

variable "alert_email" {
  description = "Email address for the CloudWatch alarm SNS subscription."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}
