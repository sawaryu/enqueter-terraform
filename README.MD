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
$ aws ssm put-parameter --name 'sample' --value 'hoge' --type String
# Update
$ aws ssm put-parameter --name 'sample' --type String --value 'hogehoge' --overwrite
# Read
$ aws ssm get-parameter --output text --name 'sample' --query Parameter.Value
# Delete
$ aws ssm delete-parameter --name "sample"
# Read as list (* Attention to dir levels)
$ aws ssm get-parameters-by-path --path "/"
```

`CloudWatch`
```bash
$ aws logs filter-log-events --log-group-name /ecs/example
```

`ECR`
```
# login
$ aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin {account_id}.dkr.ecr.ap-northeast-1.amazonaws.com  

# build
$ docker build --no-cache -t {account_id}.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest .

# push
$ docker push {account_id}.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest
```

`RDS`
```
# change identifier after apply RDS
$ aws rds modify-db-instance --db-instance-identifier "example" --master-user-password "super_secrete_identifier"
```

## Deletion Protection Resources

You need to change setting before destroy protection-resources.

1. RDS
* `deletion_protection` to `false`
* `skip_final_snapshot` to `true`

2. ALB
* `deletion_protection` to `false`

3. S3
* `force_destroy = true`