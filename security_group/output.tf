# ※超重要：securitygroupのIDは生成後に初めて知ることができる。そのためIDを使用できるようにoutput定義しておく
output "security_group_id" {
  value = aws_security_group.default.id
}