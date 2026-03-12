aws_region = "ap-northeast-1"
project    = "myapp"
env        = "dev"

# Amazon Linux 2023 (ap-northeast-1) - 最新AMIに合わせて変更すること
ec2_ami_id = "ami-0599b6e53ca798bb2"

db_name     = "myappdb"
db_username = "dbadmin"
# db_password はセキュリティのため terraform.tfvars に書かず、
# 実行時に -var="db_password=xxx" か TF_VAR_db_password 環境変数で渡すこと
