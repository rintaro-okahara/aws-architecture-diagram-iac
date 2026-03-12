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
