# Terraform

## 前提条件

- Terraform >= 1.3
- AWS CLI（プロファイル設定済み）
- Packer（AMIビルド時のみ）

---

## ディレクトリ構成

```
terraform/
├── dev/          # dev環境のルートモジュール
└── modules/
    ├── compute/  # ALB, EC2
    ├── database/ # RDS
    └── network/  # VPC, Subnet, IGW, NAT
```

---

## デプロイ手順

### 1. Golden AMIをPackerでビルドする

EC2はGolden AMI（nginxインストール済みAMI）を使って起動します。
初回デプロイおよびnginx設定を変更したときに実行します。

#### Packerのインストール

```bash
brew install packer
```

#### ベースAMI IDの確認

```bash
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-kernel-*-x86_64" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text \
  --region ap-northeast-1 \
  --profile <your-profile>
```

#### AMIのビルド

```bash
cd packer/
packer init .
packer build \
  -var "source_ami=<上で確認したAMI ID>" \
  -var "aws_profile=<your-profile>" \
  nginx.pkr.hcl
```

ビルド完了後、以下のような出力が表示されます：

```
--> amazon-ebs.nginx: AMIs were created:
ap-northeast-1: ami-0xxxxxxxxxxxxxxxxx  ← このIDをコピーする
```

### 2. AMI IDをTerraformに反映する

`terraform/dev/terraform.tfvars` の `ec2_ami_id` を更新します：

```hcl
ec2_ami_id = "ami-0xxxxxxxxxxxxxxxxx"  # Packerで作成したAMI ID
```

### 3. Terraformを実行する

```bash
cd terraform/dev/
terraform init
terraform plan
terraform apply
```

---

## AMI更新時のフロー

nginxの設定変更やOSパッチ適用をしたい場合：

1. `packer/nginx.pkr.hcl` を修正
2. `packer build` で新しいAMIを作成
3. `terraform.tfvars` の `ec2_ami_id` を新しいAMI IDに更新
4. `terraform apply` でEC2を入れ替え（既存EC2は破棄→新規作成）

---

## 注意事項

- `terraform.tfvars` はGit管理外です（`.gitignore`）。`terraform.tfvars.example` を参考に作成してください
- AMIはAWSアカウントのリージョンに保存されます。不要になったAMIはコンソールから削除してください
