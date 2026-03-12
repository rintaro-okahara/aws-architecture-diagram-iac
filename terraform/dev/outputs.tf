output "alb_dns_name" {
  description = "ALBのDNS名（ブラウザからアクセスするURL）"
  value       = module.compute.alb_dns_name
}

output "rds_endpoint" {
  description = "RDSのエンドポイント"
  value       = module.database.rds_endpoint
}

output "rds_port" {
  description = "RDSのポート番号"
  value       = module.database.rds_port
}
