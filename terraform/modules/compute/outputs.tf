output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ec2_security_group_id" {
  description = "EC2のSGのID（databaseモジュールのingressルールに使用）"
  value       = aws_security_group.ec2.id
}
