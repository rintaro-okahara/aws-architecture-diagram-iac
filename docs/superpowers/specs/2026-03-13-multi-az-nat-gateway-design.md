# Multi-AZ NAT Gateway Design

**Date:** 2026-03-13
**Status:** Draft

## Background

The current network configuration places a single NAT Gateway in AZ-a (`ap-northeast-1a`). Although subnets, EC2 instances, and the ALB are deployed across two AZs (AZ-a and AZ-c), the shared Private Route Table routes all outbound traffic through that single NAT Gateway. If AZ-a fails, outbound connectivity from AZ-c's Private Subnet is lost, defeating the purpose of the multi-AZ subnet layout.

Note: the existing `availability_zones` variable has a stale description (`AZ-a, AZ-b`) but the actual default is `["ap-northeast-1a", "ap-northeast-1c"]` (AZ-a and AZ-c). Correcting this description comment is included in scope. The inline comments in `main.tf` for subnet resources also say "AZ-b" — fixing these is explicitly out of scope to keep changes minimal.

## Goal

Enable true Multi-AZ outbound connectivity by optionally deploying a NAT Gateway in each AZ, controlled by a boolean variable so dev environments can remain cost-efficient.

## Scope

Changes are limited to two files:
- `terraform/modules/network/variables.tf` — add `enable_multi_az_nat`; fix stale `availability_zones` description
- `terraform/modules/network/main.tf` — update EIP, NAT Gateway, Private Route Table, and associations

No changes to compute or database modules are required.

To enable multi-AZ NAT in dev when needed, add the following to `terraform/dev/main.tf` module call:
```hcl
module "network" {
  ...
  enable_multi_az_nat = true
}
```
This is not required by default since `enable_multi_az_nat` defaults to `false`.

## Design

### Variable

Add `enable_multi_az_nat` to `modules/network/variables.tf`. Also fix the stale description on `availability_zones` from `"使用するAZリスト（AZ-a, AZ-b）"` to `"使用するAZリスト（AZ-a, AZ-c）"`:

```hcl
variable "enable_multi_az_nat" {
  description = "各AZにNAT Gatewayを配置するか（falseはAZ-aのみ）"
  type        = bool
  default     = false
}
```

Default is `false` to preserve the single-NAT-GW behavior for dev (cost saving).

### EIP

Change from a single resource to `count`-based:

```hcl
resource "aws_eip" "nat" {
  count  = var.enable_multi_az_nat ? 2 : 1
  domain = "vpc"
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })
}
```

### NAT Gateway

Change from a single resource to `count`-based, placing each gateway in the corresponding AZ's Public Subnet:

```hcl
resource "aws_nat_gateway" "main" {
  count         = var.enable_multi_az_nat ? 2 : 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  })
  depends_on = [aws_internet_gateway.main]
}
```

### Private Route Table

Split into per-AZ route tables so each AZ routes through its own NAT Gateway:

```hcl
resource "aws_route_table" "private" {
  count  = var.enable_multi_az_nat ? 2 : 1
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}
```

### Private Route Table Associations

The association count is always `2` because there are always 2 private subnets regardless of the NAT configuration. The ternary on `route_table_id` is what selects the correct route table per AZ — not the count. When `enable_multi_az_nat = false`, both subnets share `private[0]`; when `true`, each subnet gets its own table.

```hcl
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.enable_multi_az_nat ? count.index : 0].id
}
```

## Trade-offs Considered

| Approach | Description | Decision |
|---|---|---|
| A (chosen) | `count`-based unified control | Chosen: simple, minimal changes |
| B | Keep existing resource, add secondary separately | Rejected: verbose, duplicate logic |
| C | Count = length(availability_zones) | Rejected: over-engineered for current needs |

## Impact on Existing Resources

### Resource Address Rename (first apply)

Changing `aws_eip.nat`, `aws_nat_gateway.main`, and `aws_route_table.private` from singular resources to `count`-based renames their Terraform state addresses (e.g., `aws_nat_gateway.main` → `aws_nat_gateway.main[0]`). **This destroy+create occurs on the first apply after the code change, regardless of the value of `enable_multi_az_nat`.**

Because this is a dev environment, this is acceptable. Apply during a low-traffic window.

If zero-downtime is required (e.g., in a production environment), run `terraform state mv` from the `terraform/dev/` directory. **Take a state backup first**, because `terraform state mv` is not atomic — if a command fails midway the state will be partially renamed:

```sh
cd terraform/dev/
terraform state pull > backup.tfstate   # take a backup before starting

terraform state mv aws_eip.nat aws_eip.nat[0]
terraform state mv aws_nat_gateway.main aws_nat_gateway.main[0]
terraform state mv aws_route_table.private aws_route_table.private[0]
```

If any command fails midway, restore with `terraform state push backup.tfstate` before retrying. After all three succeed, `terraform plan` should show no destroy+create for these resources.

Note: `aws_route_table_association.private` is already `count`-based in the current code, so no `state mv` is needed for it.

### Enabling multi-AZ (`false` → `true`)

When `enable_multi_az_nat` is toggled to `true`, this is a **single `terraform apply`** — no two-pass needed. Terraform's dependency graph ensures `aws_nat_gateway.main[1]` is created before `aws_route_table.private[1]` (which references it), and the route table association is updated only after the route table is ready. The existing `[0]` resources are not affected. No outage is expected.

### Disabling multi-AZ (`true` → `false`)

Toggling back to `false` destroys `aws_eip.nat[1]`, `aws_nat_gateway.main[1]`, and `aws_route_table.private[1]`, and updates the AZ-c route table association to point back to `private[0]`. This briefly removes the AZ-c dedicated NAT route and is only acceptable in a maintenance window.

No `terraform state mv` is needed when disabling multi-AZ — Terraform cleanly destroys the `[1]` resources and there is no address rename in this direction.

## Prerequisites

Before enabling `enable_multi_az_nat = true`, verify the AWS account has sufficient EIP quota. The default limit is 5 EIPs per region. Check both current usage and the quota:

```sh
# Current usage
aws ec2 describe-addresses --query 'Addresses[*].PublicIp' --output table

# Account quota
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0263D0A3 \
  --query 'Quota.Value'
```

Enabling multi-AZ NAT increases EIP count from 1 to 2. Ensure `(current usage + 1) < quota`.

## Behavior Summary

| `enable_multi_az_nat` | NAT Gateways | Private Route Tables | AZ-a failure impact |
|---|---|---|---|
| `false` (default) | 1 (AZ-a only) | 1 (shared) | AZ-c outbound lost |
| `true` | 2 (AZ-a + AZ-c) | 2 (per-AZ) | AZ-c outbound unaffected |
