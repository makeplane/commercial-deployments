variable "name" {
  description = "Name prefix."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR."
  type        = string
}

variable "azs" {
  description = "Availability zones."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway instead of one per AZ."
  type        = bool
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
