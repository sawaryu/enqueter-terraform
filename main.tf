terraform {
  required_version = "1.0.9"
}

provider "aws" {
  region = "ap-northeast-1"
}

#------------
# ６章 バケット
#------------

resource "aws_s3_bucket_policy" "alb_log" {
  bucket = aws_s3_bucket.alb_log.id
  policy = data.aws_iam_policy_document.alb_log.json
}

data "aws_iam_policy_document" "alb_log" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]

    principals {
      type        = "AWS"
      identifiers = ["582318560864"]
    }
  }
}

resource "aws_s3_bucket" "alb_log" {
  bucket        = "alb-log-sample-bucket43756273"
  force_destroy = true

  lifecycle_rule {
    enabled = true
    expiration {
      days = "180"
    }
  }
}

#----------------
# 第7章 ネットワーク
#----------------

#--VPC--#
resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  # awsDNSサーバーによる名前解決を有効にする。
  enable_dns_support   = true
  # VPC内のリソースにパブリックDNSホスト名を自動的に割り当てる。
  enable_dns_hostnames = true 

  tags = {
    Name = "example"
  }
}

#--Public Subnet--#
resource "aws_subnet" "public_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  # このサブネット内で起動したインスタンスにパブリックIPアドレスを自動的に割り当てる。
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

#--Private Subnet--#
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

resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}
resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  #間違えやすい。applyするまでエラーが出ないためかなり注意する。
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}
resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
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

# natをpublicsubnetへ紐づける(multiAZ)
resource "aws_nat_gateway" "nat_gateway_0" {
  allocation_id = aws_eip.nat_gateway_0.id
  # パブリックサブネットを指定することに注意する（要調査）
  subnet_id     = aws_subnet.public_0.id
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
# 第8章 ロードバランサーとDNS
#----------------

#--ALB--#
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
  load_balancer_type         = "application" # applicationの指定でALB化する
  internal                   = false         # インターネット向けなのでfalseとする。
  idle_timeout               = 60            # タイムアウト
  enable_deletion_protection = true          # 削除保護

  # マルチAZ化
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

output "alb_dns_name" {
  value = aws_lb.example.dns_name
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
      # リダイレクトステータスコード
      status_code = "HTTP_301"
    }
  }
}

#--Route53--#
data "aws_route53_zone" "example" {
  name = "tubuanpanman.com"
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = data.aws_route53_zone.example.name
  type    = "A"

  # ALBのIPアドレスへの名前解決(ドメイン名>IPアドレス)
  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

output "domain_name" {
  value = aws_route53_record.example.name
}

#--ACM (SSL,https)--#
resource "aws_acm_certificate" "example" {
  domain_name               = aws_route53_record.example.name
  subject_alternative_names = []    # 例：["text.example.com"]と指定するとその分のSSL証明書も発行する。（今回は無し）
  validation_method         = "DNS" # DNS検証で所有権を検証する。自動更新する場合はこちらを選択

  lifecycle {
    #新しい証明書をつくってから古いのと差し替えることによりサービスアウトを防ぐ
    create_before_destroy = true
  }
}

# DNS検証用のDNSレコード(※バージョンアップにて記法に注意が必要。tolistの部分)
resource "aws_route53_record" "example_certificate" {
  name    = tolist(aws_acm_certificate.example.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.example.domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.example.domain_validation_options)[0].resource_record_value]
  zone_id = data.aws_route53_zone.example.id
  ttl     = 60 # time to live (生存時間)
}

# 検証待機(特殊なリソース:apply時にssl証明書の検証が終了するまで待機する。)
resource "aws_acm_certificate_validation" "example" {
  depends_on = [
    aws_acm_certificate.example
  ]
  certificate_arn = aws_acm_certificate.example.arn
  # 絶対ドメイン名
  validation_record_fqdns = [aws_route53_record.example_certificate.fqdn]
}

# alb htpps listner
resource "aws_lb_listener" "https" {
  depends_on = [
    aws_acm_certificate_validation.example
  ]
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.example.arn
  ssl_policy        = "ELBSecurityPolicy-2016-08" # aws推奨のsslポリシー

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これはHTTPSです"
      status_code  = 200
    }
  }
}

#リクエストフォワーディング（ECS(nginx)の指定ポートにリクエストを投げる）
resource "aws_lb_target_group" "nginx" {
  name                 = "nginx"
  target_type          = "ip" # fargateの場合
  vpc_id               = aws_vpc.example.id
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 300 #秒

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
  priority     = 100 # 数字が低いほど優先が高い（本来はもっと低い数字）

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
# 第9章 コンテナオーケストレーション
#----------------

#--ECS--#

# Cluster
resource "aws_ecs_cluster" "api" {
  name = "api"
}

# Task
resource "aws_ecs_task_definition" "api" {
  family                   = "api" # タスク定義名（リビジョンがインクリメントされていく。最初は[example:1]）
  cpu                      = "256"     # memory*cpuの組み合わせは決まっているので注意する。
  memory                   = "512"
  network_mode             = "awsvpc" # 起動タイプfargateの場合は必ずawsvpcモード
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./container_definitions.json") #コンテナ定義（深堀していく必要がある。）

  # コンテナ間socket通信用
  volume {
    name = "socket"
  }

  # Dockerコンテナがcloudwatchにログを投げられるように関連づける
  execution_role_arn = module.ecs_task_execution_role.iam_role_arn
}

# Service
resource "aws_ecs_service" "api" {
  name                              = "api"                           # 前述のクラスタ定義名を指定
  cluster                           = aws_ecs_cluster.api.arn         # 前述のクラスタ定義arnを指定
  task_definition                   = aws_ecs_task_definition.api.arn #　前述のタスク定義arn
  desired_count                     = 1                               #希望のコンテナ起動維持数(※本番の際は２にする)
  launch_type                       = "FARGATE"
  platform_version                  = "1.4.0" #最新のものを指定しよう(*1.3.0 > から最新のものに変更済み)
  health_check_grace_period_seconds = 60      # 再起動ループを抑止するために多少ゆとりにある秒数を設定

  network_configuration {
    assign_public_ip = false # privateネットワークで起動のため不要（公開ALBからprivateへ接続する流れか？）
    security_groups  = [module.nginx_sg.security_group_id]

    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  # albのリクエストフォワード定義と関連づける。
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx" #　task_difinitionsより参照
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [
      task_definition
    ]
  }
}

module "nginx_sg" {
  source      = "./security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = [aws_vpc.example.cidr_block]
}


resource "aws_cloudwatch_log_group" "for_ecs" {
  name              = "/ecs/example"
  retention_in_days = 180
}

# role定義
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution" {
  source_json = data.aws_iam_policy.ecs_task_execution_role_policy.policy

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}

module "ecs_task_execution_role" {
  source     = "./iam_role"
  name       = "ecs-task-execution"
  identifier = "ecs-tasks.amazonaws.com"
  policy     = data.aws_iam_policy_document.ecs_task_execution.json
}

#----------------
# 第11 章鍵管理
#----------------

#--KMS--#

# カスタマーキーの作成
resource "aws_kms_key" "example" {
  description             = "Example Customer Master Key"
  enable_key_rotation     = true # 年に一度の自動ローテーション機能
  is_enabled              = true # カスタマーキーの有効化。適宜無効とすることもできる。
  deletion_window_in_days = 30   # キーの削除取り消し猶予期間日数(一度削除したら元には戻せないので注意)
}

# カスタマーキーはUUIDが割り当てられ非常に読みづらいため、alias設定する。
resource "aws_kms_alias" "example" {
  name          = "alias/example" # "alias/"プレフィックスが必須
  target_key_id = aws_kms_key.example.id
}

#----------------
# 第13章 データストア（RDS）※12章の内容（ssm）も含む
#----------------

#--RDS--#

# 設定
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

# define subnet with RDS
resource "aws_db_subnet_group" "example" {
  name       = "example"
  subnet_ids = [aws_subnet.private_0.id, aws_subnet.private_1.id] # to multiAZ
}

resource "aws_ssm_parameter" "db_username" {
  name        = "/db/username"
  value       = "admin"
  type        = "String"
  description = "db user name"
}

# 作成後にCLIで直接の変更が必要
resource "aws_ssm_parameter" "db_password" {
  name        = "/db/password"
  value       = "uninitialized"
  type        = "SecureString"
  description = "db password"

  # valueの変更を検知しない。
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

resource "aws_db_instance" "example" {
  identifier                 = "example"
  engine                     = "mysql"
  engine_version             = "5.7.25" #バッチバージョンまで含める必要がある。
  instance_class             = "db.t3.small"
  allocated_storage          = 20    #デフォルト容量
  max_allocated_storage      = 100   #最大スケール容量
  storage_type               = "gp2" #汎用SSD
  storage_encrypted          = true
  kms_key_id                 = aws_kms_key.example.arn # ディスク暗号化が有効になる。(arnであることに注意)
  username                   = "admin"
  password                   = "supremepassword!" #平文管理は危険なため変更の必要がある
  multi_az                   = true
  publicly_accessible        = false                 #vpc外からのアクセスを遮断する
  backup_window              = "09:10-09:40"         #utcでバックアップタイミングを指定する(メンテナンスの前に設定するのが定石)
  backup_retention_period    = 30                    #バックアップ保存期間
  maintenance_window         = "mon:10:10-mon:10:40" #定期メンテナンスのタイミングを指定する
  auto_minor_version_upgrade = false
  deletion_protection        = true  #削除保護
  skip_final_snapshot        = false #削除時にスナップショットを作成したいため
  port                       = 3306
  apply_immediately          = false #設定変更のタイミング(一部の設定変更に対して再起動が伴うため？要調査)
  vpc_security_group_ids     = [module.mysql_sg.security_group_id]
  parameter_group_name       = aws_db_parameter_group.example.name
  db_subnet_group_name       = aws_db_subnet_group.example.name

  lifecycle {
    #後から手動で変更を与えるため管理外とする。
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



#----------------
# 第14章 デプロイメントパイプライン
#----------------

#--ECR--#
resource "aws_ecr_repository" "api" {
  name = "api"
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "keep last 30 release tagged images",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["release"],
          "countType": "imageCountMoreThan",
          "countNumber": 30
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
EOF
}

resource "aws_ecr_repository" "nginx" {
  name = "nginx"
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name

  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "keep last 30 release tagged images",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["release"],
          "countType": "imageCountMoreThan",
          "countNumber": 30
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
EOF
}
