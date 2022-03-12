#----------------
# VPC
#----------------
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
  # Enable aws-DNS to take the name solutuon
  enable_dns_support = true
  # Automatic allocation of DNS hostname for resources in this VPC
  enable_dns_hostnames = true

  tags = {
    Name = "example"
  }
}

#----------------
# Subnet
#----------------
resource "aws_subnet" "public_0" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.1.0/24"
  # Automatic allocation of public IP-addresses for instances which start in this subnet
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
}
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1c"
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.example.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public_0" {
  subnet_id      = aws_subnet.public_0.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.65.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
}
resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

#----------------
# NAT
#----------------
resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}

resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}
resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_eip" "nat_gateway_0" {
  vpc = true
  depends_on = [
    aws_internet_gateway.example
  ]
}
resource "aws_eip" "nat_gateway_1" {
  vpc = true
  depends_on = [
    aws_internet_gateway.example
  ]
}

resource "aws_nat_gateway" "nat_gateway_0" {
  allocation_id = aws_eip.nat_gateway_0.id
  # Attention to setting public subnet in below
  subnet_id = aws_subnet.public_0.id
  depends_on = [
    aws_internet_gateway.example
  ]
}
resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on = [
    aws_internet_gateway.example
  ]
}

#----------------
# ALB, DNS
#----------------
module "http_sg" {
  source      = "./security_group"
  name        = "http-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}
module "https_sg" {
  source      = "./security_group"
  name        = "https-sg"
  vpc_id      = aws_vpc.example.id
  port        = 443
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_lb" "example" {
  name                       = "example"
  load_balancer_type         = "application" # If you want to "ALB", set "application"
  internal                   = false         # For internet, this is "false"
  idle_timeout               = 60            # timeout
  enable_deletion_protection = true          # protection from deletion

  # Multi AZ
  subnets = [
    aws_subnet.public_0.id,
    aws_subnet.public_1.id,
  ]

  access_logs {
    bucket  = aws_s3_bucket.alb_log.id
    enabled = true
  }

  security_groups = [
    module.http_sg.security_group_id,
    module.https_sg.security_group_id
  ]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port     = "443"
      protocol = "HTTPS"
      # Status code of "redirect"
      status_code = "HTTP_301"
    }
  }
}

# ALB htpps listner
resource "aws_lb_listener" "https" {
  depends_on = [
    aws_acm_certificate_validation.example
  ]
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.example.arn
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Recommended SSL policy by AWS

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "This is HTTPS"
      status_code  = 200
    }
  }
}

# Request forwarding to nginx port "80"
resource "aws_lb_target_group" "nginx" {
  name                 = "nginx"
  target_type          = "ip" # In case of "FARGATE"
  vpc_id               = aws_vpc.example.id
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 300 # seconds

  health_check {
    path                = "/"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = 200
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  depends_on = [
    aws_lb.example
  ]
}

resource "aws_lb_listener_rule" "nginx" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100 # The lower this number, the prioryty is higher (*originaly, priority is more lower)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

#----------------
# Route53, ACM(SSL certificate)
#----------------
variable "api_domain_name" {}

data "aws_route53_zone" "example" {
  name = var.api_domain_name
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = data.aws_route53_zone.example.name
  type    = "A"

  # Name solution for ALB IP-address (Dimain name -> IP-address )
  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "example" {
  domain_name               = aws_route53_record.example.name
  subject_alternative_names = []    # .eg: Create another certiciction for "text.example.com" (This time nothing)
  validation_method         = "DNS" # Testing DNS ownership. This option enable automatic updating.

  lifecycle {
    # Prevent from service-out by creating new SSL certification before destroying old one.
    create_before_destroy = true
  }
}

# DNS record for testing DNS (* attention to "tolist" grammer by terraform version.)
resource "aws_route53_record" "example_certificate" {
  name    = tolist(aws_acm_certificate.example.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.example.domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.example.domain_validation_options)[0].resource_record_value]
  zone_id = data.aws_route53_zone.example.id
  ttl     = 60 # time to live
}

# Special resouce. Await until testting SSL certificate has been complete when apply.
resource "aws_acm_certificate_validation" "example" {
  depends_on = [
    aws_acm_certificate.example
  ]
  certificate_arn = aws_acm_certificate.example.arn
  # Fully Qualified Domain Name (FQDN)
  validation_record_fqdns = [aws_route53_record.example_certificate.fqdn]
}

#----------------
# VPC ENDPOINT
#----------------

# module "private_link_sg" {
#   source      = "./security_group"
#   name        = "private-link-sg"
#   vpc_id      = aws_vpc.example.id
#   port        = 443
#   cidr_blocks = [aws_vpc.example.cidr_block]
# }

# resource "aws_vpc_endpoint" "ecr_api" {
#   vpc_id              = aws_vpc.example.id
#   subnet_ids          = [aws_subnet.private_0.id, aws_subnet.private_1.id]
#   service_name        = "com.amazonaws.ap-northeast-1.ecr.api"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true

#   security_group_ids = [module.private_link_sg.security_group_id]

#   tags = {
#     Name = "ecr-api"
#   }
# }

# resource "aws_vpc_endpoint" "ecr_dkr" {
#   vpc_id              = aws_vpc.example.id
#   subnet_ids          = [aws_subnet.private_0.id, aws_subnet.private_1.id]
#   service_name        = "com.amazonaws.ap-northeast-1.ecr.dkr"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true

#   security_group_ids = [module.private_link_sg.security_group_id]

#   tags = {
#     Name = "ecr-dkr"
#   }
# }

# resource "aws_vpc_endpoint" "watch_logs" {
#   vpc_id              = aws_vpc.example.id
#   subnet_ids          = [aws_subnet.private_0.id, aws_subnet.private_1.id]
#   service_name        = "com.amazonaws.ap-northeast-1.logs"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true

#   security_group_ids = [module.private_link_sg.security_group_id]

#   tags = {
#     Name = "watch-logs"
#   }
# }

# resource "aws_vpc_endpoint" "ssm" {
#   vpc_id              = aws_vpc.example.id
#   subnet_ids          = [aws_subnet.private_0.id, aws_subnet.private_1.id]
#   service_name        = "com.amazonaws.ap-northeast-1.ssm"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true

#   security_group_ids = [module.private_link_sg.security_group_id]

#   tags = {
#     Name = "ssm"
#   }
# }

# resource "aws_vpc_endpoint" "s3_gateway" {
#   vpc_id            = aws_vpc.example.id
#   service_name      = "com.amazonaws.ap-northeast-1.s3"
#   vpc_endpoint_type = "Gateway"

#   tags = {
#     Name = "s3-gateway"
#   }

#   route_table_ids = [aws_route_table.private_0.id, aws_route_table.private_1.id]
# }

# resource "aws_route_table" "private_0" {
#   vpc_id = aws_vpc.example.id
# }

# resource "aws_route_table" "private_1" {
#   vpc_id = aws_vpc.example.id
# }

# resource "aws_route_table_association" "s3_gateway_0" {
#   subnet_id      = aws_subnet.private_0.id
#   route_table_id = aws_route_table.private_0.id
# }
# resource "aws_route_table_association" "s3_gateway_1" {
#   subnet_id      = aws_subnet.private_1.id
#   route_table_id = aws_route_table.private_1.id
# }


