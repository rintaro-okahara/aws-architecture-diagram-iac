variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "プロジェクト名（タグ・命名に使用）"
  type        = string
}

variable "env" {
  description = "環境名"
  type        = string
  default     = "dev"
}

variable "ec2_ami_id" {
  description = "EC2のAMI ID"
  type        = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}
