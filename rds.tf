#----------------
# KSM key management
#----------------
resource "aws_kms_key" "example" {
  description             = "Example Customer Master Key"
  enable_key_rotation     = true # annual key lotation.
  is_enabled              = true # Literaly enable or false (* cna be change anytime).
  deletion_window_in_days = 30   # deletion rollback periods (* the operation of deletion can't be canceled).
}

# Default is UUID. recommend to allocate alias for easier reading.
resource "aws_kms_alias" "example" {
  name          = "alias/example" # * "alias/" prefix is must need.
  target_key_id = aws_kms_key.example.id
}

#----------------
# RDS, SSM
#----------------
resource "aws_db_parameter_group" "example" {
  name   = "example"
  family = "mysql5.7"

  parameter {
    name  = "character_set_database"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
}
resource "aws_db_subnet_group" "example" {
  name       = "example"
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id] # Multi AZ.
}

resource "aws_ssm_parameter" "db_username" {
  name        = "/db/username"
  value       = "admin"
  type        = "String"
  description = "db user name"
}

# * For secret value. you must need change the value after apply.
resource "aws_ssm_parameter" "db_password" {
  name        = "/db/password"
  value       = "uninitialized"
  type        = "SecureString"
  description = "db password"

  # Ignore changing value.
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

resource "aws_db_instance" "example" {
  identifier                 = "example"
  engine                     = "mysql"
  engine_version             = "5.7.25" # Need patch version
  instance_class             = "db.t3.small"
  allocated_storage          = 20    # Default storage size
  max_allocated_storage      = 100   # Max scalable storage
  storage_type               = "gp2" # SSD
  storage_encrypted          = true
  kms_key_id                 = aws_kms_key.example.arn # Disk encryption (*arn)
  name                       = "exampledb"
  username                   = "admin"
  password                   = "supremepassword!" # ** Must change after applying **
  multi_az                   = true
  publicly_accessible        = false         # Disable access from out of VPC
  backup_window              = "09:10-09:40" # Backup schedule (* should set before maintenance_window)
  backup_retention_period    = 30
  maintenance_window         = "mon:10:10-mon:10:40" # Maintenance schedule
  auto_minor_version_upgrade = false
  deletion_protection        = true  # Delete protection (* you must need change to "false" before destroy)
  skip_final_snapshot        = false # (* you must need change to "true" before destroy)
  port                       = 3306
  apply_immediately          = false # Timing of changing setting
  vpc_security_group_ids     = [module.mysql_sg.security_group_id]
  parameter_group_name       = aws_db_parameter_group.example.name
  db_subnet_group_name       = aws_db_subnet_group.example.name

  lifecycle {
    # Ignore password change, Because changing the password after apply
    ignore_changes = [
      password
    ]
  }
}

module "mysql_sg" {
  source      = "./security_group"
  name        = "mysql-sg"
  vpc_id      = aws_vpc.example.id
  port        = 3306
  cidr_blocks = [aws_vpc.example.cidr_block]
}
