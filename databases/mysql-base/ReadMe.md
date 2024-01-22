### Naming
The name of the AMI will determine access and settings used not only for the AMI but also for the EC2 instance when deployed.

Following elements will use the name

Secrets Manager (ASM) containing login details used by the AMI and the deployed EC2 instance.<br>
/infrastructure/credentials/mysql-[**name**]

SSH keyname for the instance<br>
mysql-[**name**]-[environment]-[region]

AMI name<br>
mysql-[**name**]-primer-[environment]-[date]-[time]

The new AMI can be deployed by Terraform or manually. After deployment the schema(s) and users need to be added manually. For backups please follow the backup policy.<br>
If replication is required the replica instance should be deployed into a different region than the main instance.
To set up replication, please follow the instructions setup replication.

### Prerequisites
1. Create SSH key.
2. Create login details in ASM.<br>Details include root user (local access only) password and administrator user name and password for reote access over VPN.
