# These names are global (DNS), so they carry a suffix.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  suffix = random_id.suffix.hex

  postgres_name = "${var.name}-pg-${local.suffix}"
  redis_name    = "${var.name}-redis-${local.suffix}"
  # Key Vault: 3-24 characters, no consecutive hyphens.
  key_vault_name = "${replace(substr(replace(var.name, "/-+/", "-"), 0, 12), "/-$/", "")}-kv-${local.suffix}"
  # Storage account: 3-24 lowercase letters and digits.
  storage_account_name = "${substr(replace(var.name, "-", ""), 0, 16)}${local.suffix}"
}
