# ds-ami-build
Building AMIs for services in AWS

Currently the snapshots are stored in the accounts which will deploy the AMIs. This allows the AMIs being encrypted using the AWS generated keys rather than introducing our own encrypttion key handling. 
## Action Steps
1. Authenticate with AWS
2. Assume role in AWS account
3. Create required resources for the target instance (security groups, instance role/profile)
4. Start up primer instance; running initial bash script copying needed files from S3
5. Wait until primer instance is in stable condition
6. Create AMI from primer instance
7. Terminate primer instance
8. Remove not needed resources created in point #3
## Prerequisites
### AWS
- account s-devops-ansible-amis in tna-iam with assume role permission
- role s-devops-ansible-amis with permission in EC2, S3, IAM and Secrets Manager
### Action Secrets (repo-wide)
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
### Action Secrets (each environment - dev, staging and production)
- AWS_ACCOUNT_ID - target account for storing the AMI
- AWS_ROLE_ARN - role s-devops-ansible-amis in target account
- SSH_KEY - ssh private key used to log in to primer instance and the deployed instance. Note, this is the contents of the key, not the filename!
- SUBNET_ID - public subnet in target account
- VPC_ID - vpc of the public subnet
### GitHub Actions/Ansible
- branching for each environment - dev, staging and production

# AMI Bookkeeping
## Primer instance
Over the time the process accumulates many AMIs which are incurring costs. From time to time it will be necessary to remove old and redundant images.\
It is also important to remove primer instances, produced temporarily by the process, after a failed build.
These images are easily recognisable as the name will contain the word *-primer-*.\
Please be aware that _other ami build processes use the same naming convention_ which includes *=primer-* in their instance names. If required narrow down the name for the instance you want to delete.

`aws ec2 describe-instances --filter "Name=tag:Name,Values=*-primer-*" --query "Reservations[*].Instances[*].InstanceId" --output text`

and us the instance ids returned with this statement\

`terminate-instances --instance-ids i-1234567890abcdef0 i-abcdef0123456789`

## Faulty AMIs
If the resulting AMI is faulty or shouldn't be use for other reasons it needs be deregister.\
To identify the latest built AMI use following command\
`aws ec2 describe-images --filter "Name=name,Values=discovery-web-*" --query "reverse(sort_by(Images, &CreationDate))[1].ImageId" --output json`\
_Please change the value for the filter to match the ami as close as possible._\

and to deregister the images use command \
`aws ec2 deregister-image --image-id i-1234567890abcdef0`\
_The id should be replace by the result from the describe-images command._/

## Redundant AMIs
As a target we don't to keep older AMIs which won't be used anymore. A good target is probably three AMIs of a workflow at a time. This allows to have a rollback version and another older spare version.

To only see the AMIs which could be potentially deregistered following the target of three relevant AMIs use command\
'aws ec2 describe-images --filter "Name=name,Values=discovery-web-*" --query "reverse(sort_by(Images, &CreationDate))[3:].ImageId" --output json'

and to deregister the images use command \
`aws ec2 deregister-image --image-id i-1234567890abcdef0`\
_The id should be replace by the result from the describe-images command._/

To see all AMIs including if they were launched use command\
`aws ec2 describe-images --filter "Name=name,Values=discovery-web-*" --query "reverse(sort_by(Images, &CreationDate))[3:].ImageId" --output json | jq -r -c '.[]' | while read id; do aws ec2 describe-image-attribute --attribute lastLaunchedTime --image-id $id --output text; done`\


>!!! Dangerzone !!!\
>Using above loop to deregister AMIs might remove images which are in use. Use the following command with caution!\
>
>aws ec2 describe-images --filter "Name=name,Values=discovery-web-*" --query "reverse(sort_by(Images, &CreationDate))[3:].ImageId" --output json | jq -r -c '.[]' | while read id; do aws ec2 deregister-image --image-id $id; done

## Deployment of AMIs
Visit the repos of each service to read about the steps of deployment which are required.

[Blog](https://github.com/nationalarchives/ds-infrastructure-blog) - Blog WordPress website\
[Discovery Infrastructure](https://github.com/nationalarchives/ds-infrastructure-discovery) & [Discovery CodeDeploy](https://github.com/nationalarchives/discovery)\
[Media](https://github.com/nationalarchives/ds-infrastructure-media) - Media WordPress website\
[Website](https://github.com/nationalarchives/ds-infrastructure-media) - Main WordPress website\

