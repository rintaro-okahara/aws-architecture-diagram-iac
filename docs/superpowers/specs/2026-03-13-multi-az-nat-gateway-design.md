# Multi-AZ NAT Gateway Design

**Date:** 2026-03-13
**Status:** Approved

## Background

The current network configuration places a single NAT Gateway in AZ-a (`ap-northeast-1a`). Although subnets, EC2 instances, and the ALB are deployed across two AZs (AZ-a and AZ-c), the shared Private Route Table routes all outbound traffic through that single NAT Gateway. If AZ-a fails, outbound connectivity from AZ-c's Private Subnet is lost, defeating the purpose of the multi-AZ subnet layout.

## Goal

Enable true Multi-AZ outbound connectivity by optionally deploying a NAT Gateway in each AZ, controlled by a boolean variable so dev environments can remain cost-efficient.

## Scope

Changes are limited to two files:
- `terraform/modules/network/variables.tf`
- `terraform/modules/network/main.tf`

No changes to `dev/main.tf`, compute module, or database module.

## Design

### Variable

Add `enable_multi_az_nat` to `modules/network/variables.tf`:

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

Always iterate over all 2 private subnets, but reference the correct route table index:

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

Because `aws_nat_gateway.main` changes from a singular resource to an indexed one (`main` → `main[0]`), Terraform will plan a **destroy + create** for the existing NAT Gateway and its EIP. This is acceptable in a dev environment where no production traffic is affected.

## Behavior Summary

| `enable_multi_az_nat` | NAT Gateways | Private Route Tables | AZ-a failure impact |
|---|---|---|---|
| `false` (default) | 1 (AZ-a only) | 1 (shared) | AZ-c outbound lost |
| `true` | 2 (AZ-a + AZ-c) | 2 (per-AZ) | AZ-c outbound unaffected |
