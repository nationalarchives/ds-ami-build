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
### Action Secrets (each environment - dev, staging and production)
- AWS_ACCESS_KEY_ID
- AWS_ACCOUNT_ID - target account for storing the AMI
- AWS_ROLE_ARN - role s-devops-ansible-amis in target account
- AWS_SECRET_ACCESS_KEY
- SSH_KEY - ssh key used to log in to primer instance and the deployed instance
- SUBNET_ID - public subnet in target account
- VPC_ID - vpc of the public subnet
### GitHub Actions/Ansible
- branching for each environment - dev, staging and production
