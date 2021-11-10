variable "name" {}
variable "vpc_id" {}
variable "port" {}
variable "cidr_blocks" {
  type = list(string)
}

resource "aws_security_group" "default" {
  name   = var.name
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "ingress" {
  type              = "ingress"
  from_port         = var.port #http通信を許可(リクエスト)
  to_port           = var.port #出口も許可（レスポンス）
  protocol          = "tcp"
  cidr_blocks       = var.cidr_blocks #全てのipから
  security_group_id = aws_security_group.default.id
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0    #あらゆるポートからの発信を許可
  to_port           = 0    #あらゆるポートへのアクセスを許可
  protocol          = "-1" #全てのプロトコル("all")
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id
}

# ※超重要：securitygroupのIDは生成後に初めて知ることができる。そのためIDを使用できるようにoutput定義しておく
output "security_group_id" {
  value = aws_security_group.default.id
}
