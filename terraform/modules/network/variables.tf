variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnetのCIDRリスト（AZ-a, AZ-b）"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnetのCIDRリスト（AZ-a, AZ-b）"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_subnet_cidrs" {
  description = "DB subnetのCIDRリスト（AZ-a, AZ-b）"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "availability_zones" {
  description = "使用するAZリスト（AZ-a, AZ-b）"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}
