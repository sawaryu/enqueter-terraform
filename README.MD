# Enqueter Terraform

Infrastructure by terraform

## AWS CLI setup
<u>1. Install latest one</u>
```
$ curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
$ sudo installer -pkg AWSCLIV2.pkg -target /
```


<u>2. aws configure</u>
```
$ aws configure
AWS Access Key ID [None]: *access_key_id
AWS Secret Access Key [None]: *secret_access_key_id
Default region name [None]: *region_name
Default output format [None]: *("json" is better.)
```

```
# Setting list
$ aws configure list
# Get account ID
$ aws sts get-caller-identity --query Account --output text
```

## AWS CLI operation

`SSM`
```bash
# Create
$ aws ssm put-parameter --name 'sample_name' --value 'hoge' --type String
# Update
$ aws ssm put-parameter --name 'sample_name' --type String --value 'hogehoge' --overwrite
# Read
$ aws ssm get-parameter --output text --name 'sample_name' --query Parameter.Value
# Delete
$ aws ssm delete-parameter --name "sample_name"
# Read as list
$ aws ssm get-parameters-by-path --path "/"
```

`CloudWatch`
```bash
$ aws logs filter-log-events --log-group-name /ecs/example
```

`ECR`
```
# login
$ aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin 123456789123.dkr.ecr.ap-northeast-1.amazonaws.com  

# build
$ docker build -t 123456789123.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest .

# push
$ docker push 123456789123.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest
```

`RDS`
```
# change identifier
$ aws rds modify-db-instance --db-instance-identifier "example" --master-user-password "super_secrete_identifier"
```

## Attention

1. VPC default root is out of terraform operation.
2. Route53 domains life time is one year.
3. Before Destroy RDS
* `deletion_protection` to `false`
* `skip_final_snapshot` to `true`
* `terraform apply destroy`

## Deletion Protection Resources

In case of "terraform destroy", needing confirm setting.

1. ALB
2. RDB
3. S3 (* `force_destroy = true`)