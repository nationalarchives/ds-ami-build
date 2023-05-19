# Creating a shared MySQL instance
## Surrounding infrastructure
The EC2 instance is placed in a private subnet to avoid exposure to any access from outside AWS.
The security group should only allow port 3306 to be exposed to the private subnets of the account.
The data will be written to a persistent EBS volume which will be mounted to the instance. If the EBS isn't attached, no data can be accessed.
The MySQL database will have contain several schemas which are currently:
1. Blog
2. Media
3. Website
4. CommandPapers

All schemas have their own user allowing the applications access only to their specific data.

The root account only can access the DB locally. There is an additional administration account to allow maintenance remotely with MySQL Workbench.
Access via Workbench is only possible when using a ClientVPN connection or an instance, running in the account.
Login details are maintained in Secrets Manager. Please be aware of the user name and password requirements of MySQL.
## Initial install of MySQL on EBS
Follow the [documentation on the AWS website](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html) to initialse the EBS
and attach the new EBS to the instance:
Please use /mysql as the mount directory as this will be used from the actual instance running the shared MySQL database.

After attaching the new EBS to an instance and the installation of MySQL, the default data location should be copied to the EBS.
```bash
mkdir /mysql/data
mkdir /mysql/log
sudo systemctl stop mysqld
sudo cp -rap /var/lib/mysql/. /mysql/data
```
You also need to change the my.cnf file to point to the new location
```bazaar
sudo sed -i 's/datadir=\/var\/lib\/mysql/datadir=\/mysql\/data/g' /etc/my.cnf
sudo sed -i 's/log-error=\/var\/log\/mysqld.log/log-error=\/mysql\/log\/mysqld.log/g' /etc/my.cnf
```
After the above steps you should be able to access the database with Workbench and being able to run all tasks to maintain the schemas and users.
To create users and schemas please refer to MySQL documentation.
After the initial process to create the data on the EBS, there isn't any need to revisit the steps above as they might cause data loss.

## Installing a shared MySQL DB instance
The process to create an instance which allows to connect to the MySQL database is done by GitHub Actions.

This process will create an AMI which can be used to create a new instance or replace an already existing one. Please be aware that simply replacing the instance will bring some downtime and should be done only in dev and staging.

