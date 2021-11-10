# Create infrastructure from Terraform
* 書籍「実践Terraform」を参考にAWSのクラウドインフラを`terraform`を使用してコードで開発、運用していく。
継続的デリバリー（CD）に関してはCircleCIを使用予定で、当該書籍の範囲から超えているためそれなりに応用的な実装が求められそう。

* アプリケーションに関してはまずpythonでもなんでもよいので最小単位のもので練習として概要を掴む。CDパイプラインを構築できたらゴールとして進める。可能であればRDSへの関連付けも完了した最小単位のAPIをデプロイしたい。

* また、Terraformの管理から外れるリソースやその他注意事項についても積極的にここにまとめていく。（※`terraform destroy`で管理できないリソースや`環境変数`等）

* `aws provider`, `terraform`ともに非常にバージョンアップが激しいため情報の鮮度等には注意して対応していく。

# AWS CLI setup
Terraformの仕様にはAWS CLIのセットアップが必要なので一応いかに手順をまとめておく。
1. 最新インストール
```
$ curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
$ sudo installer -pkg AWSCLIV2.pkg -target /

--# 確認
$ which aws
$ aws --version
```

2. aws configure
```
$ aws configure
AWS Access Key ID [None]: アクセスキー ID
AWS Secret Access Key [None]: シークレットアクセスキー
Default region name [None]: ap-northeast-1
Default output format [None]: 
```

```
--# 確認
$ aws configure list
  or
$ aws sts get-caller-identity --query Account --output text
(account id が正しく表示されていればOK)
```

# メモ（まずは箇条書き）
* S3にオブジェクトが残っていると`terraform destroy`では削除できない。（リソースに`force_destroy = true`を指定すれば解決）
※ただし扱いには注意すること。

* VPC内の通信を有効にするためにローカルルートが自動的に作られる。（生成タイミングは不明、必要調査）Terraformでの管理ができないので少し注意が必要だ。

* ALBの削除保護設定
`enable_deletion_protection = true`とすると`terraform destroy`の対象外となる。
削除するには`false`に変更後`apply(適用) > destroy(削除)`を行う
```bash
resource "aws_lb" "example" {
  name                       = "example"
  load_balancer_type         = "application" # applicationの指定でALB化する
  internal                   = false # インターネット向けなのでfalseとする。
  idle_timeout               = 60 # タイムアウト
  enable_deletion_protection = true # 削除保護(!!この部分)

  subnets = [
    aws_subnet.public_0.id,
    aws_subnet.public_1.id,
  ]

  :
  省略
  :
```

* Domain名(Rouet53)※超重要
ドメインの自動更新は無効としている（１年で期限切れ。→要管理）
つぶあんぱんまん
`tubuanpanman.com`
```
ドメインの登録はterraformの管理外のため、コンソールから行う。
```
* SSL導入時の`terraform apply`エラーについて
DNS検証が完了する前にhttpsのリスナーが起動してしまい資格がないものとしてエラーと思われる。
```
Error: error creating ELBv2 Listener (arn:aws:elasticloadbalancing:ap-northeast-1:132180986458:loadbalancer/app/example/1518da073e7f3e8a): UnsupportedCertificate: The certificate 'arn:aws:acm:ap-northeast-1:132180986458:certificate/b74cfb29-dda0-4016-b84b-9da1099d7f34' must have a fully-qualified domain name, a supported signature, and a supported key size.
│       status code: 400, request id: c08e4d1f-d443-4da9-8272-9014fe2d2a36
│ 
│   with aws_lb_listener.https,
│   on main.tf line 356, in resource "aws_lb_listener" "https":
│  356: resource "aws_lb_listener" "https" {
```
上記から二つのリソースに独自に`depends_on`を追加済み
※今後この部分で問題が生じるようであれば適宜対応する。
```
resource "aws_acm_certificate_validation" "example" {
  depends_on = [
    aws_acm_certificate.example
  ]
  certificate_arn = aws_acm_certificate.example.arn
  validation_record_fqdns = [aws_route53_record.example_certificate.fqdn]
}

resource "aws_lb_listener" "https" {
  depends_on = [
    aws_acm_certificate_validation.example
  ]
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.example.arn
  ssl_policy        = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これはHTTPSです"
      status_code  = 200
    }
  }
}
```

* タスク定義で使用する`container_difinitons.json`について

```
[
  {
    "name": "example", # 任意にcontainernameを設定
    "image": "nginx:latest", # 最新のnginxイメージを選定
    "essential": true, # タスクの実行に際して必須のコンテナかどうか
    "portMappings": [ # 文字通りマッピングするコンテナポートと外部ポート
      {
        "protocol": "tcp",
        "containerPort": 80
      }
    ]
  }
]
```

* `arn`とは

amazon resouce name のこと
要調査

* タスク定義の変更について

argateの場合デプロイのたびにタスク定義が更新され、plan時に差異が生じるためterraformでタスク定義の変更を無視する）その一方で（タスク定義を変更する際は一時的に外すなどの対処が必要か？）
```
resource "aws_ecs_task_definition" "example" {
  :
  省略
  :

  load_balancer {
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example" #　task_difinitionsより参照
    container_port   = 80
  }

  lifecycle {
    # なかなか重要（fargateの場合デプロイのたびにタスク定義が更新され、plan時に差異が生じるためterraformでタスク定義の変更を無視する）
    # その一方で（タスク定義を変更する際は一時的に外すなどの対処が必要か？）
    ignore_changes = [
      task_definition
    ]
  }
}
```

* http > https リダイレクトリスナーについて

```
# redirect http to https listner(これは試験的なリダイレクトテスト？本来なら80http > 443https にリダイレクトするべきでは？)
resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "8080"
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
```

* `CloudWatch`のlog確認
```bash
# 確認したいロググループ名を指定する。
$ aws logs filter-log-events --log-group-name /ecs/example
```

* `SSM`の管理、操作

ssmパラメータストアへの値操作

```bash
# 保存
$ aws ssm put-parameter --name 'sample_name' --value 'sample' --type String

# 上書き
$ aws ssm put-parameter --name 'sample_name' --type String --value 'samplemodified' --overwrite

# 読み取り
$ aws ssm get-parameter --output text --name 'sample_name' --query Parameter.Value

# 削除
$ aws ssm delete-parameter --name "sample_name"

# 一括確認(※階層で確認することに注意する)
$ aws ssm get-parameters-by-path --path "/"
```

以下apply後に手動で変更済み（そのまま平分保存はアンチパターン）
```yml
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
```

* `aws_cloudwatch_event_target`の挙動があまりに不明
```
タスク起動 > image pull // ここまではOK 
↓
タスク停止 > タスク起動　>  image pull失敗 > タスク停止 // 左記のループに入る
```

## RDSリソースの管理

1. 主要な設定項目
パスワードはterraform上で平文管理せずapply後に既存のパスワードを変更する。
またパスワードdockerコンテナで参照できるようにssm管理(type: SecureString)するのがよいかもしれない。
ssmはSecureStringであってもリソース内部で透過的に扱うことができる。

```
$ aws rds modify-db-instance --db-instance-identifier "example" --master-user-password "hogehoge"
```

2. RDSの削除
RDSを削除するには以下の下準備が必要(※任意のリソースのみdestroyする方法もありそうなのでこちらは調査が必要かも)
* `deletion_protection`をfalseに変更する。
* `skip_final_snapshot`をtrueにする。
* apply > destroy

## repositoryへのプッシュ
```
# login
$ aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin 132180986458.dkr.ecr.ap-northeast-1.amazonaws.com  

# build
$ docker build -t 132180986458.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest .

# push
$ docker push 132180986458.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest
```

# .tfstateファイルの管理
.tfstateファイルはバージョン管理システムでの管理が非推奨。
チーム開発の際に複数人が同時にapplyした場合それぞれのstateファイルの内容が分岐してしまい競合が発生してしまう。
※ただし、今回のケースに限っては個人での開発のため状態が分岐することは考えにくいため例外としてバージョン管理システムでファイル管理を行う。

* 注意点

`terraform init`の際に生成される`.terraform`ディレクトリはバイナリファイルを含み非常に重くGitHubでの管理ができないためgitignoreする。