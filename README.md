# This project provisions a wordpress EKS cluster.

The project uses terraform to initialize the following:

* VPC with 3 private subnets and 3 public subnets in 3 availability zones
* NAT gateway
* EFS file system for persistent storage 
* EKS cluster of 3 nodes in the private subnets
* Bastion host in a public subnet 
* RDS database in a private subnet with multi-az
* Security groups for the bastion host, eks nodes and rds
* policy and role to the eks cluster with permissions for efs

The EKS nodes will run a deployment of wordpress pods with a load balancer service, a persistent volume (efs) and a mysql database (rds).
You can use the bastion host to connect to the private nodes if needed, with ssh agent forwarding that will forward your key pair to the nodes.
for example:

eval `ssh-agent` - will start the ssh agent process
ssh-add *your key.pem*
ssh -A ec2-user@IP
ssh ec2-user@INTERNAL-IP

*** NOTE ***

If you are on Linux, please change the shared_credentials_file in the providers.tf file to your credentials location.
If you are using any region other than us-east-1, please change the default region variable in the variables.tf file or use terraform apply -var region="value".

## Project requirments:

1. terraform    https://www.terraform.io/downloads
2. aws cli      https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
3. helm         https://helm.sh/docs/intro/install/
4. eksctl       https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
5. kubectl      https://kubernetes.io/docs/tasks/tools/
6. default aws credentials (if you're using profiles you should modify the terraform file accordingly)
7. a key pair in your machine

## Installation guide:

* Go the the terraform folder and run terraform plan to see the resources that will be created and then terraform apply or terraform apply -auto-approve (This step could take 15-20 minutes so be patient). You have to give terraform the rds password and username you want the rds database to have and your key pair name.

* Run the command: aws eks update-kubeconfig --region *region* --name eks-cluster (It will allow your machine to connect to the EKS control plane).

* Run the command: eksctl utils associate-iam-oidc-provider --cluster eks-cluster --approve (The oidc provider is needed for the cluster to work with efs).

* Use terraform state show aws_iam_policy.worker_policy_efs or use the aws console/cli and copy the policy arn.

* Use eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster eks-cluster \
    --attach-policy-arn *Your copyied arn* \
    --approve \
    --override-existing-serviceaccounts \
    --region region-code

This command will bind your iam role with the policy that terraform created to a service account (You can also create a service account manually, if you want to do so please consult the documentation).

* Use helm to install the EFS driver:
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=123456789012.dkr.ecr.region-code.amazonaws.com/eks/aws-efs-csi-driver \ # change this image according to your region: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html this is the container image of the efs driver.
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa

* Navigate to the kubernetes folder and edit the storageclass.yaml file, enter your EFS file system id, save the file and run kubectl apply -f storageclass.yaml
Now kubernetes knows how to create a persistent volume with EFS.

* Edit the kustomization.yaml file and enter your rds username and password that you've chosen, as well as the rds endpoint and name (you can find them in the rds console or with terraform state show). The wordpress deployment will use these secrets to connect to the RDS database.

* Run kubectl apply -k ./
It will initialize the deployment with the secret and persistent volume claim and create a persistent volume dynamically.

* Run kubectl apply -f wordpress-service.yaml
It will create an ELB with an endpoint which you can use to consume the application.
You can find the URL in the console or with kubectl get service.