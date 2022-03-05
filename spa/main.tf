#----------------
# S3
#----------------

locals {
  bucket_name  = var.app_name
  s3_origin_id = "S3-${var.app_name}"
}
resource "aws_s3_bucket" "enqueter" {
  bucket        = local.bucket_name
  force_destroy = true
}
resource "aws_s3_bucket_policy" "enqueter" {
  bucket = aws_s3_bucket.enqueter.id
  policy = data.template_file.s3_policy.rendered
}
resource "aws_s3_bucket_public_access_block" "enqueter" {
  bucket                  = aws_s3_bucket.enqueter.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
data "template_file" "s3_policy" {
  template = file("./spa/s3_policy.json")
  vars = {
    origin_access_identity = aws_cloudfront_origin_access_identity.enqueter.id
    bucket_name            = local.bucket_name
  }
}
data "aws_route53_zone" "enqueter" {
  name         = var.front_domain_name
  private_zone = false
}

#----------------
# CroudFront
#----------------
resource "aws_cloudfront_origin_access_identity" "enqueter" {
  comment = var.app_name
}
resource "aws_cloudfront_distribution" "enqueter" {
  aliases = [var.front_domain_name]
  origin {
    domain_name = aws_s3_bucket.enqueter.bucket_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.enqueter.cloudfront_access_identity_path
    }
  }
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  # In case of stopping sevice, "false"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  default_root_object = "index.html"

  custom_error_response {
    error_caching_min_ttl = 300 # Defautl 5 minutes.
    error_code            = 403 # Custome error code.
    response_code         = 200 # Response code you want.
    response_page_path    = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn      = var.acm_id
    minimum_protocol_version = "TLSv1.2_2019"
    ssl_support_method       = "sni-only"
  }
}

resource "aws_route53_record" "enqueter" {
  type    = "A"
  name    = var.front_domain_name
  zone_id = data.aws_route53_zone.enqueter.id
  alias {
    name                   = aws_cloudfront_distribution.enqueter.domain_name
    zone_id                = aws_cloudfront_distribution.enqueter.hosted_zone_id
    evaluate_target_health = false
  }
}
