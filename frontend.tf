#------------
# FRONTEND
#------------
module "acm" {
  source = "./acm"
  domain = "ichimonittou.com"
}

module "spa" {
  source   = "./spa"
  domain   = "ichimonittou.com"
  app_name = "ichimonittou-front"
  acm_id   = module.acm.acm_id
}
