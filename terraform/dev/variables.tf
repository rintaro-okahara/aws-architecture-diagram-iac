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
