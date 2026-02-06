provider "aws" {
  region = var.region

  default_tags {
    tags = merge(
      { Provider = "plane.so" },
      var.tags
    )
  }
}
