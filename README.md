# This project provisions a wordpress EKS cluster.

NOTE:

This project has recently been updated to reflect on a lot of changes from the last two years.
IAM policies were updated.
A lot of the syntax in the EKS module was deprecated so it has been updated to work with the latest version.
The bastion host is no logner living in a public subnet and does not have any public IP and SSH access.
You can only access it via SSM in the AWS console or CLI which is the best practice.
DB subnets have been added, so application subnets are private and have NAT gateways and DB subnets don't have access to the internet at all.
A folder for provisioning remote tfstate S3 bucket and DynamoDB has been added.
Updated EKS to use version 1.26
Updated the bastion host to use Amazon Linux 2023

The project uses terraform to initialize the following:

* VPC with 3 db subnets, 3 private subnets and 3 public subnets in 3 availability zones
* NAT gateway per az
* EFS file system for persistent storage 
* EKS cluster of 3 nodes in each private subnet
* Bastion host in the private subnet for administrating the eks cluster and terraform 
* RDS database in a db non-internet subnet with multi-az
* Security groups for the bastion host, eks nodes and rds
* policy and role to the eks cluster with permissions for efs

The EKS nodes will run a deployment of wordpress pods with a load balancer service, a persistent volume (efs) and a mysql database (rds).

## Project requirments:

1. terraform    https://www.terraform.io/downloads
2. aws cli      https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
3. helm         https://helm.sh/docs/intro/install/
4. eksctl       https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
5. kubectl      https://kubernetes.io/docs/tasks/tools/
6. default aws credentials (if you're using profiles you should modify the terraform file accordingly)

## Installation guide:

* Go to the tfstate-resources folder and run terraform init and then terraform apply to create the S3 for storing the tfstate remotly and the DynamoDB table for lock override prevention.
Because S3 buckets have to have a unique name, a random_string terraform resource is implemented to add a random suffix, so after the bucket is created, go to the terraform folder and update the bucket name there in the providers.tf file.

* Go the the terraform folder and run terraform init to install the provider's plugins, terraform plan to see the resources that will be created and then terraform apply or terraform apply -auto-approve (This step could take 15-20 minutes so be patient). You have to give terraform the rds password and username you want the rds database to have and you can edit them in the terraform.tfvars file.

* The best practice is to no longer access the cluster from outside of the VPC, so you can login to the bastion which will have all the necessary tools, and clone the terraform repository, change the cluster_endpoint_public_access value in the main.tf file from true to false, so no one would be able to access the cluster endpoint outside of the VPC so only the bastion host could use kubectl to manage the cluster.

* Run the command: aws eks update-kubeconfig --region *region-code* --name *cluster name* (It will allow your machine to connect to the EKS control plane).

* Run the command: eksctl utils associate-iam-oidc-provider --cluster *cluster name* --approve (The oidc provider is needed for the cluster to work with efs).

* Use terraform state show aws_iam_policy.worker_policy_efs or use the aws console/cli and copy the policy arn.

* Use eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster *cluster name* \
    --attach-policy-arn *your copied arn* \
    --approve \
    --override-existing-serviceaccounts \
    --region *region-code*

This command will bind your iam role with the policy that terraform created to a service account (You can also create a service account manually, if you want to do so please consult the documentation).

* Use helm to install the EFS driver:

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/

helm repo update

helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=<region-registry>.dkr.ecr.<region-code>.amazonaws.com/eks/aws-efs-csi-driver \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa

change the image according to your region: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html this is the container image of the efs driver.

* Navigate to the kubernetes folder and edit the storageclass.yaml file, enter your EFS file system id, save the file and run kubectl apply -f storageclass.yaml
Now kubernetes knows how to create a persistent volume with EFS.

* Edit the kustomization.yaml file and enter your rds username and password that you've chosen, as well as the rds endpoint and name (you can find them in the rds console or with terraform state show). The wordpress deployment will use these secrets to connect to the RDS database.

* Run kubectl apply -k ./
It will initialize the deployment with the secret and persistent volume claim and create a persistent volume dynamically.

* Run kubectl apply -f wordpress-service.yaml
It will create an ELB with an endpoint which you can use to consume the application.
You can find the URL in the console or with kubectl get service.
