packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "aws_profile" {
  type    = string
  default = ""
}

variable "source_ami" {
  type        = string
  description = "ベースAMI (Amazon Linux 2023, ap-northeast-1)"
  # 最新のAmazon Linux 2023 AMIに更新すること
  # 確認コマンド:
  #   aws ec2 describe-images \
  #     --owners amazon \
  #     --filters "Name=name,Values=al2023-ami-2023*-kernel-*-x86_64" \
  #     --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  #     --output text --region ap-northeast-1
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

source "amazon-ebs" "nginx" {
  region          = var.aws_region
  profile         = var.aws_profile
  instance_type   = var.instance_type
  source_ami      = var.source_ami
  ssh_username    = "ec2-user"
  ami_name        = "myapp-nginx-{{timestamp}}"
  ami_description = "Golden AMI: Amazon Linux 2023 + nginx"

  tags = {
    Name    = "myapp-nginx"
    Base    = "amazon-linux-2023"
    Builder = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.nginx"]

  provisioner "shell" {
    inline = [
      "sudo dnf install -y nginx",
      "sudo systemctl enable nginx",
    ]
  }
}
