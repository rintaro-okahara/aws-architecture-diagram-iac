# Terraform AWS Architecture Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** VPC・ALB・EC2・RDS（Multi-AZ）をモジュール構成（network/compute/database）でTerraformを実装する。

**Architecture:** `modules/network` でVPC/Subnet/NAT/RouteTableを管理し、その出力を `modules/compute`（ALB・EC2）と `modules/database`（RDS）に渡す3層構造。`terraform/dev/` がモジュールを呼び出すルート設定。

**Tech Stack:** Terraform >= 1.3、AWS Provider ~> 5.0、ローカルstate

---

### Task 1: ディレクトリ構造とプロバイダー設定

**Files:**
- Create: `terraform/modules/network/main.tf`
- Create: `terraform/modules/network/variables.tf`
- Create: `terraform/modules/network/outputs.tf`
- Create: `terraform/modules/compute/main.tf`
- Create: `terraform/modules/compute/variables.tf`
- Create: `terraform/modules/compute/outputs.tf`
- Create: `terraform/modules/database/main.tf`
- Create: `terraform/modules/database/variables.tf`
- Create: `terraform/modules/database/outputs.tf`
- Modify: `terraform/dev/main.tf`
- Modify: `terraform/dev/variables.tf`
- Modify: `terraform/dev/outputs.tf`
- Modify: `terraform/dev/terraform.tfvars`

**Step 1: モジュールディレクトリを作成**

```bash
mkdir -p terraform/modules/network
mkdir -p terraform/modules/compute
mkdir -p terraform/modules/database
```

**Step 2: 各モジュールに空ファイルを作成**

```bash
touch terraform/modules/network/main.tf terraform/modules/network/variables.tf terraform/modules/network/outputs.tf
touch terraform/modules/compute/main.tf terraform/modules/compute/variables.tf terraform/modules/compute/outputs.tf
touch terraform/modules/database/main.tf terraform/modules/database/variables.tf terraform/modules/database/outputs.tf
```

**Step 3: `terraform/dev/main.tf` にプロバイダー設定を記述**

```hcl
terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

**Step 4: `terraform/dev/variables.tf` に基本変数を定義**

```hcl
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
```

**Step 5: `terraform/dev/terraform.tfvars` に値を記述**

```hcl
aws_region = "ap-northeast-1"
project    = "myapp"
env        = "dev"
```

**Step 6: terraform init して構文確認**

```bash
cd terraform/dev
terraform init
terraform validate
```
期待値: `Success! The configuration is valid.`

**Step 7: コミット**

```bash
git add terraform/
git commit -m "feat: scaffold terraform module structure and provider config"
```

---

### Task 2: network モジュール実装

**Files:**
- Modify: `terraform/modules/network/variables.tf`
- Modify: `terraform/modules/network/main.tf`
- Modify: `terraform/modules/network/outputs.tf`

**Step 1: `modules/network/variables.tf` を記述**

```hcl
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
```

**Step 2: `modules/network/main.tf` を記述**

```hcl
locals {
  name_prefix = "${var.project}-${var.env}"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# Public Subnets (AZ-a, AZ-b)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  }
}

# Private Subnets (AZ-a, AZ-b)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
  }
}

# DB Subnets (AZ-a, AZ-b)
resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-db-subnet-${count.index + 1}"
    Type = "DB"
  }
}

# EIP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

# NAT Gateway (AZ-a の Public Subnet に配置)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Table: Public (IGW経由)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

# Route Table: Private (NAT経由)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

# Route Table: DB (外部ルートなし)
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-db-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
```

**Step 3: `modules/network/outputs.tf` を記述**

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}
```

**Step 4: `terraform/dev/main.tf` にnetworkモジュール呼び出しを追記**

```hcl
module "network" {
  source  = "../modules/network"
  project = var.project
  env     = var.env
}
```

**Step 5: validate**

```bash
cd terraform/dev
terraform init
terraform validate
```
期待値: `Success! The configuration is valid.`

**Step 6: コミット**

```bash
git add terraform/
git commit -m "feat: implement network module (VPC, subnets, IGW, NAT, route tables)"
```

---

### Task 3: compute モジュール実装

**Files:**
- Modify: `terraform/modules/compute/variables.tf`
- Modify: `terraform/modules/compute/main.tf`
- Modify: `terraform/modules/compute/outputs.tf`
- Modify: `terraform/dev/main.tf`
- Modify: `terraform/dev/variables.tf`

**Step 1: `modules/compute/variables.tf` を記述**

```hcl
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
```

**Step 2: `modules/compute/main.tf` を記述**

```hcl
locals {
  name_prefix = "${var.project}-${var.env}"
}

# Security Group: ALB
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# Security Group: EC2
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ec2-sg"
  }
}

# ALB
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "main" {
  name     = "${local.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

# Listener: HTTP 80
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# EC2 Instances (AZ-a, AZ-b)
resource "aws_instance" "app" {
  count         = 2
  ami           = var.ec2_ami_id
  instance_type = var.ec2_instance_type
  subnet_id     = var.private_subnet_ids[count.index]

  vpc_security_group_ids = [aws_security_group.ec2.id]

  tags = {
    Name = "${local.name_prefix}-app-${count.index + 1}"
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "app" {
  count            = 2
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.app[count.index].id
  port             = 80
}
```

**Step 3: `modules/compute/outputs.tf` を記述**

```hcl
output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ec2_security_group_id" {
  description = "EC2のSGのID（databaseモジュールのingressルールに使用）"
  value       = aws_security_group.ec2.id
}
```

**Step 4: `terraform/dev/variables.tf` にEC2変数を追記**

```hcl
variable "ec2_ami_id" {
  description = "EC2のAMI ID"
  type        = string
}
```

**Step 5: `terraform/dev/terraform.tfvars` にAMI IDを追記**

```hcl
# Amazon Linux 2023 (ap-northeast-1) - 最新AMIに合わせて変更すること
ec2_ami_id = "ami-0599b6e53ca798bb2"
```

**Step 6: `terraform/dev/main.tf` にcomputeモジュール呼び出しを追記**

```hcl
module "compute" {
  source             = "../modules/compute"
  project            = var.project
  env                = var.env
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  ec2_ami_id         = var.ec2_ami_id
}
```

**Step 7: validate**

```bash
cd terraform/dev
terraform init
terraform validate
```
期待値: `Success! The configuration is valid.`

**Step 8: コミット**

```bash
git add terraform/
git commit -m "feat: implement compute module (ALB, EC2, security groups)"
```

---

### Task 4: database モジュール実装

**Files:**
- Modify: `terraform/modules/database/variables.tf`
- Modify: `terraform/modules/database/main.tf`
- Modify: `terraform/modules/database/outputs.tf`
- Modify: `terraform/dev/main.tf`
- Modify: `terraform/dev/variables.tf`
- Modify: `terraform/dev/terraform.tfvars`

**Step 1: `modules/database/variables.tf` を記述**

```hcl
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
```

**Step 2: `modules/database/main.tf` を記述**

```hcl
locals {
  name_prefix = "${var.project}-${var.env}"
}

# Security Group: RDS
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL from EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ec2_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# RDS Instance (PostgreSQL, Multi-AZ)
resource "aws_db_instance" "main" {
  identifier             = "${local.name_prefix}-rds"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = var.multi_az
  skip_final_snapshot    = true
  publicly_accessible    = false

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}
```

**Step 3: `modules/database/outputs.tf` を記述**

```hcl
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "rds_port" {
  value = aws_db_instance.main.port
}
```

**Step 4: `terraform/dev/variables.tf` にDB変数を追記**

```hcl
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
```

**Step 5: `terraform/dev/terraform.tfvars` にDB値を追記**

```hcl
db_name     = "myappdb"
db_username = "dbadmin"
# db_password はセキュリティのため terraform.tfvars に書かず、
# 実行時に -var="db_password=xxx" か TF_VAR_db_password 環境変数で渡すこと
```

**Step 6: `terraform/dev/main.tf` にdatabaseモジュール呼び出しを追記**

```hcl
module "database" {
  source                = "../modules/database"
  project               = var.project
  env                   = var.env
  vpc_id                = module.network.vpc_id
  db_subnet_ids         = module.network.db_subnet_ids
  ec2_security_group_id = module.compute.ec2_security_group_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
}
```

**Step 7: validate**

```bash
cd terraform/dev
terraform init
terraform validate
```
期待値: `Success! The configuration is valid.`

**Step 8: コミット**

```bash
git add terraform/
git commit -m "feat: implement database module (RDS PostgreSQL Multi-AZ, DB subnet group)"
```

---

### Task 5: outputs.tf を完成させる

**Files:**
- Modify: `terraform/dev/outputs.tf`

**Step 1: `terraform/dev/outputs.tf` を記述**

```hcl
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
```

**Step 2: validate**

```bash
cd terraform/dev
terraform validate
```
期待値: `Success! The configuration is valid.`

**Step 3: terraform plan の確認（オプション・AWSクレデンシャルがある場合）**

```bash
cd terraform/dev
TF_VAR_db_password="yourpassword" terraform plan
```
期待値: `Plan: 24 to add, 0 to change, 0 to destroy.`

**Step 4: コミット**

```bash
git add terraform/dev/outputs.tf
git commit -m "feat: add root outputs (ALB DNS, RDS endpoint)"
```

---

## .gitignore の確認

`terraform/dev/.gitignore` に以下が含まれていることを確認（なければ追加）:

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars.backup
.terraform.lock.hcl  # ロックファイルはプロジェクト方針による
```

## 注意事項

- `db_password` は `terraform.tfvars` に書かないこと。環境変数 `TF_VAR_db_password` で渡す。
- `ec2_ami_id` は東京リージョン（ap-northeast-1）の最新AMIを確認して更新すること。
- `terraform apply` を実行するにはAWSクレデンシャル（`~/.aws/credentials` または環境変数）が必要。
- RDSの `multi_az = true` は料金が2倍になるため、dev環境では `false` にしてもよい。その場合は `terraform.tfvars` で上書き可能。
