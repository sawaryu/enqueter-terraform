resource "aws_security_group" "default" {
  name   = var.name
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "ingress" {
  type              = "ingress"
  from_port         = var.port # Basically,permit only http
  to_port           = var.port #
  protocol          = "tcp"
  cidr_blocks       = var.cidr_blocks
  security_group_id = aws_security_group.default.id
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0    # Permit all port from app
  to_port           = 0    # Permit all access from any port
  protocol          = "-1" # All protocol
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id
}