variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name — used in resource tags and naming"
  type        = string
  default     = "devops-platform-lab"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type — t3.small minimum (Jenkins needs 2 GB RAM)"
  type        = string
  default     = "t3.small"
}

variable "public_key" {
  description = "SSH public key content — Terraform creates the AWS key pair from this. Set via TF_VAR_public_key (scripts/setup-prerequisites.sh does this). Leave null to use SSM only."
  type        = string
  default     = null
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDRs allowed SSH + Jenkins access (home, work, hotspot). Primary access via SSM — SSH is fallback."
  type        = list(string)
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB — minimum 30GB required by Amazon Linux 2023 AMI"
  type        = number
  default     = 30
}
