provider "aws" {
  region = var.region

  default_tags {
    tags = merge(
      { kustomize-provider = "plane.so" },
      var.tags
    )
  }
}
