variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "ALBを配置するPublic SubnetのIDリスト"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "EC2を配置するPrivate SubnetのIDリスト"
  type        = list(string)
}

variable "ec2_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ec2_ami_id" {
  description = "EC2のAMI ID（Amazon Linux 2023推奨）"
  type        = string
}

variable "enable_https" {
  description = "true にするとHTTPSリスナーを追加可能な構造になる（現時点はフラグのみ）"
  type        = bool
  default     = false
}
