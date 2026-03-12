# Terraform AWS Architecture Design

Date: 2026-03-12

## Overview

AWSのVPCベースのマルチAZ構成をTerraformで実装する。
モジュール構成はネットワーク/コンピュート/データベースのレイヤー構造に対応させる。

## Architecture

```
VPC (10.0.0.0/16)
├── Public Subnet AZ-a (10.0.1.0/24)  → ALB, NAT Gateway
├── Public Subnet AZ-b (10.0.2.0/24)  → ALB
├── Private Subnet AZ-a (10.0.11.0/24) → EC2
├── Private Subnet AZ-b (10.0.12.0/24) → EC2
├── DB Subnet AZ-a (10.0.21.0/24)     → RDS (Multi-AZ)
└── DB Subnet AZ-b (10.0.22.0/24)     → RDS (Multi-AZ)
```

## Decisions

| 項目 | 決定 |
|---|---|
| Terraformファイル構成 | モジュール構成（network / compute / database） |
| Stateバックエンド | ローカル |
| RDSエンジン | PostgreSQL |
| EC2インスタンスタイプ | t3.micro（プレースホルダー） |
| ALB | HTTP 80番のみ（`enable_https`変数でHTTPS拡張可能） |

## File Structure

```
terraform/
  dev/
    main.tf          # モジュール呼び出しのみ
    variables.tf     # 環境変数定義
    terraform.tfvars # 実際の値（dev環境用）
    outputs.tf       # 出力値（ALB DNS等）
    backend.hcl      # ローカルstate
  modules/
    network/
      main.tf        # VPC, Subnet×6, IGW, NAT GW, Route Table×3, Association×6
      variables.tf
      outputs.tf
    compute/
      main.tf        # ALB, Target Group, Listener, EC2×2, Security Group×2
      variables.tf
      outputs.tf
    database/
      main.tf        # RDS (Multi-AZ), DB Subnet Group, Security Group
      variables.tf
      outputs.tf
```

## Module Details

### network

**リソース:**
- `aws_vpc`
- `aws_subnet` × 6（Public×2, Private×2, DB×2）
- `aws_internet_gateway`
- `aws_eip`（NAT Gateway用）
- `aws_nat_gateway`（Public AZ-a）
- `aws_route_table` × 3（Public/Private/DB）
- `aws_route_table_association` × 6

**outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `db_subnet_ids`

### compute

**リソース:**
- `aws_security_group` × 2（ALB用、EC2用）
- `aws_lb`（Application Load Balancer）
- `aws_lb_target_group`
- `aws_lb_listener`（HTTP 80番）
- `aws_instance` × 2（Private Subnet AZ-a/b）
- `aws_lb_target_group_attachment` × 2

**variables:** `enable_https` (bool, default: false)

**outputs:** `alb_dns_name`

### database

**リソース:**
- `aws_security_group`（EC2 SGからのみ 5432番許可）
- `aws_db_subnet_group`
- `aws_db_instance`（PostgreSQL, Multi-AZ: true）

**variables:** `db_name`, `db_username`, `db_password`, `db_instance_class`, `multi_az`

**outputs:** `rds_endpoint`, `rds_port`

## Module Dependencies

```
network → compute  (vpc_id, public_subnet_ids, private_subnet_ids)
network → database (vpc_id, db_subnet_ids)
compute → database (ec2_security_group_id)
```
