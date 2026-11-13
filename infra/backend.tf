terraform {
  backend "s3" {
    bucket       = "team13-tfstate-1794602952"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
