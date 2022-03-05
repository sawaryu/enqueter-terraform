#------------
# FRONTEND
#------------

# From .tfvars
variable "front_domain_name" {}

module "acm" {
  source            = "./acm"
  front_domain_name = var.front_domain_name
}

module "spa" {
  source            = "./spa"
  front_domain_name = var.front_domain_name
  app_name          = "enqueter-front"
  acm_id            = module.acm.acm_id
}
