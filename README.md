# This project provisions a wordpress EKS cluster.

NOTE:

This project has recently been updated to reflect on a lot of changes from the last two years in AWS and EKS in particular.

_CAUTION_

Although I applied as many best practices and security implementations as possible, this is still a personal project.
Use in production on your own risk!

_Security Features_

- The RDS database is located in db subnets (multi-az RDS) with no internet access, and only private IPs within the private subnets range can access it.
- The EC2 instances are located in private subnets with no public IP, the have internet access through NAT Gateway in each AZ.

* No SSH access is allowed to the EC2 instances, only through AWS SSM which is the most secure option.
* EBS volumes of the EC2 instances and RDS database are encrypted with AWS KMS Managed key.
* EFS volumes are encrypted with AWS KMS Managed key.
* Only IMDSv2 is allowed on the instances which is the more secure implementation of the metadata service.
* IAM policies are least privilage

The project uses terraform to initialize the following:

- VPC with 3 db subnets, 3 private subnets and 3 public subnets in 3 availability zones
- NAT gateway per az
- EFS file system for persistent storage
- EKS cluster of 3 nodes in each private subnet
- Bastion host in the private subnet for administrating the eks cluster and terraform
- RDS database in a db non-internet subnet with multi-az
- Security groups for the bastion host, eks nodes and rds
- policy and role to the eks cluster with permissions for efs

The EKS nodes will run a deployment of wordpress pods with a load balancer service, a persistent volume (efs) and a mysql database (rds).

## Project requirments:

1. terraform https://www.terraform.io/downloads
2. aws cli https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
3. helm https://helm.sh/docs/intro/install/
4. eksctl https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
5. kubectl https://kubernetes.io/docs/tasks/tools/
6. default aws credentials (if you're using profiles you should modify the terraform file accordingly)

## Installation guide:

- Go to the tfstate-resources folder and run terraform init and then terraform apply to create the S3 for storing the tfstate remotly and the DynamoDB table for lock override prevention.
  Because S3 buckets have to have a unique name, a random_string terraform resource is implemented to add a random suffix, so after the bucket is created, go to the terraform folder and update the bucket name there in the providers.tf file.

- Go the the terraform folder and run terraform init to install the provider's plugins, terraform plan to see the resources that will be created and then terraform apply or terraform apply -auto-approve (This step could take 15-20 minutes so be patient). You have to give terraform the rds password and username you want the rds database to have and you can edit them in the terraform.tfvars file.

- The best practice is to no longer access the cluster from outside of the VPC, so you can login to the bastion which will have all the necessary tools, and clone the terraform repository, change the cluster_endpoint_public_access value in the main.tf file from true to false, so no one would be able to access the cluster endpoint outside of the VPC so only the bastion host could use kubectl to manage the cluster.

- Run the command: aws eks update-kubeconfig --region _region-code_ --name _cluster-name_ (It will allow your machine to connect to the EKS control plane).

- Use eksctl to create iamserviceaccount for EFS:

```sh
export cluster_name=cluster-eks-lab

export role_name=AmazonEKS_EFS_CSI_DriverRole

eksctl create iamserviceaccount \
--name efs-csi-controller-sa \
--namespace kube-system \
--cluster $cluster_name \
--role-name $role_name \
--role-only \
--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
--region us-east-1 \
--approve

TRUST_POLICY=$(aws iam get-role --role-name $role_name --query 'Role.AssumeRolePolicyDocument' | sed -e 's/efs-csi-controller-sa/efs-csi-\*/' -e 's/StringEquals/StringLike/')

aws iam update-assume-role-policy --role-name $role_name --policy-document "$TRUST_POLICY"
```

This command will bind your iam role with the policy that terraform created to a service account (You can also create a service account manually, if you want to do so please consult the documentation).

- Navigate to the kubernetes folder and edit the storageclass.yaml file, enter your EFS file system id, save the file and run kubectl apply -f storageclass.yaml
  Now kubernetes knows how to create a persistent volume with EFS.

- Edit the kustomization.yaml file and enter your rds username and password that you've chosen, as well as the rds endpoint and database name (you can find them in the rds console or with terraform state show). The wordpress deployment will use these secrets to connect to the RDS database.

- Run kubectl apply -k ./
  It will initialize the deployment with the secret and persistent volume claim and create a persistent volume dynamically.

- Run kubectl apply -f wordpress-service.yaml
  It will create an ELB with an endpoint which you can use to consume the application.
  You can find the URL in the console or with kubectl get service.
  Use the URL of the load balancer like so http://url/wp-admin.
