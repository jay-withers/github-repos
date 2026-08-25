terraform {
  # >= 1.7 for `for_each` on `import` blocks (see imports.tf).
  required_version = ">= 1.7"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# Token comes from the GITHUB_TOKEN env var (the provider's default) - never
# hardcode it here. Locally that's a personal PAT with admin rights on every
# repo below; in CI it's the TF_GITHUB_TOKEN repository secret. See
# terraform/README.md for how to create and scope it.
provider "github" {
  owner = "jay-withers"
}
