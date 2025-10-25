# variables.tf

variable "account_id" {
  description = "Your AWS Account ID"
  type        = string
  default     = "6820xxxxxxx"
}

variable "project_name" {
  description = "A unique prefix for your resources"
  type        = string
  default     = "serverless-pwned-checker"
}