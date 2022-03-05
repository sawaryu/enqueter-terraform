#------------
# FRONTEND
#------------
variable "front_domain_name" {}

module "acm" {
  source = "./acm"
  domain = var.front_domain_name
}

module "spa" {
  source   = "./spa"
  domain   = var.front_domain_name
  app_name = "ichimonittou-front"
  acm_id   = module.acm.acm_id
}
