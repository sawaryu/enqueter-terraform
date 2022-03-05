#----------------
# ACM (virginia)
#----------------

provider "aws" {
  region = "us-east-1" # virginia region
  alias  = "virginia"  # alias
}

resource "aws_acm_certificate" "enqueter" {
  provider          = aws.virginia
  domain_name       = var.front_domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_route53_record" "enqueter" {
  depends_on = [aws_acm_certificate.enqueter]
  for_each = {
    for dvo in aws_acm_certificate.enqueter.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.enqueter.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}
resource "aws_acm_certificate_validation" "enqueter" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.enqueter.arn
  validation_record_fqdns = [for record in aws_route53_record.enqueter : record.fqdn]
}

data "aws_route53_zone" "enqueter" {
  name         = var.front_domain_name
  private_zone = false
}

output "acm_id" {
  value = aws_acm_certificate.enqueter.id
}
