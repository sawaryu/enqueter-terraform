# Very important. You can get SG id only after created.
output "security_group_id" {
  value = aws_security_group.default.id
}