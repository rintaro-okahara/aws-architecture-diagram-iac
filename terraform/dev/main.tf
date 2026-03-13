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
  profile = var.aws_profile
}

module "network" {
  source  = "../modules/network"
  project = var.project
  env     = var.env
}

module "compute" {
  source             = "../modules/compute"
  project            = var.project
  env                = var.env
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  ec2_ami_id         = var.ec2_ami_id
}

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

resource "aws_resourcegroups_group" "main" {
  name = "${var.project}-${var.env}-rg"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Project"
          Values = [var.project]
        },
        {
          Key    = "Env"
          Values = [var.env]
        }
      ]
    })
  }

  tags = {
    Name    = "${var.project}-${var.env}-rg"
    Project = var.project
    Env     = var.env
  }
}
