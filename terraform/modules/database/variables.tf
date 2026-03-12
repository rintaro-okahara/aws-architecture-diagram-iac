variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_ids" {
  description = "RDSを配置するDB SubnetのIDリスト"
  type        = list(string)
}

variable "ec2_security_group_id" {
  description = "EC2のSG ID（RDSへのingressルールに使用）"
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

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "multi_az" {
  type    = bool
  default = true
}
