AsgInstanceLaunchFailures
	
You've reached your quota for maximum Fleet Requests for this account. Launching EC2 instance failed.
	
eks-my-node-group-92cc04ed-6137-b558-121c-911ca4bb1113


— this explains why your EKS Node Group is stuck.
================================================

❌ Error Explanation

AsgInstanceLaunchFailures

    You've reached your quota for maximum Fleet Requests for this account. Launching EC2 instance failed.

This is an EC2 quota (limit) issue, specifically related to "Fleet Requests", which are used behind the scenes by EKS-managed node groups and EC2 Auto Scaling Groups.


💡 What Are Fleet Requests?

EKS uses EC2 Fleet or Auto Scaling Groups to provision instances for the node group. This error means you're hitting a soft quota limit on how many concurrent fleet requests you can make — possibly 0 or 1 is allowed, and you're exceeding it.


✅ Solutions
🔧 1. Request a Quota Increase

This is the recommended fix.
👉 Steps:

    Go to AWS Console → Service Quotas

    Filter for EC2

    Search: "Fleet requests" (you want something like: EC2 Fleet requests)

    Click it → Request increase (e.g., increase from 0 or 1 to 5+)

🕓 Approval usually takes a few minutes to hours depending on your AWS support level.




🧪 2. Workaround: Use Launch Template (Advanced)

You can avoid fleet API usage by:

    Creating your own EC2 Launch Template

    Using an aws_eks_node_group with launch_template

But this is more advanced and not always reliable for new accounts.



🔧 3. Check and Clean Up Other Resources

Sometimes, this is triggered by:

    Existing EC2 Auto Scaling Groups or Node Groups

    Stale failed EKS node groups

Try deleting anything unused:


aws eks delete-nodegroup \
  --cluster-name my-eks-cluster \
  --nodegroup-name my-node-group \
  --region ap-south-2

Then re-run Terraform.


✅ Next Steps

I recommend:

    Immediately request a quota increase for EC2 Fleet Requests

    Then retry the Terraform apply once it's approved.

Would you like help identifying the exact quota name for your region/account via CLI or Console? I can do that too.





why this:
========


 — let's break down why this happens, especially in new or low-usage AWS accounts.


❓ Why Are You Seeing the “Fleet Requests” Quota Error?
🚨 The error:

    “You've reached your quota for maximum Fleet Requests for this account.”

This is caused by your AWS account hitting the default limit (quota) on EC2 Fleet requests. Here's why this matters:

🔍 What is an EC2 Fleet Request?

    EKS-managed node groups and Auto Scaling Groups (ASGs) use a feature called EC2 Fleet to request EC2 instances.

    Even if you're asking for 1 instance, it uses a Fleet API under the hood to support things like:

        Launch templates

        Multiple instance types

        Spot/On-demand fallback

        Availability zone balancing


🧯 AWS Default Quotas Are Very Low for New Accounts

    Many AWS accounts start with:

        0 or 1 concurrent EC2 fleet request quota

    This is a soft quota, and AWS intentionally sets it low to prevent abuse or runaway costs.

    💬 In other words, you’re not doing anything wrong — AWS is just being cautious.



🧰 Quota Causing the Problem

The specific quota causing your issue is:

    EC2 → "EC2 Fleet Requests"
    (Sometimes listed as "Launches of EC2 Fleet instances" or similar)

When this quota is exhausted:

    EC2 Auto Scaling can't launch instances

    Your EKS node group creation fails with AsgInstanceLaunchFailures



✅ How to Fix It
🔧 Request Quota Increase:

    Go to: https://console.aws.amazon.com/servicequotas/home

    In the left menu, click EC2

    Find the quota for:

        EC2 Fleet requests or Launches of EC2 Fleet instances

    Click it → Request increase (e.g., from 1 → 10)

🕓 This usually takes:

    5–30 minutes with AWS Basic Support

    Faster with Business/Enterprise support plans

🧠 TL;DR
🔍 What Happened	           🛠️ Why It Happens	                            ✅ How to Fix
EKS node group failed	       AWS account limit on EC2 Fleet requests hit	   Request quota increase for “EC2 Fleet Requests” in Service Quotas



Would you like me to guide you step-by-step through the AWS Console to request this increase, or would you prefer a CLI command to do it?


any other option:
=================

Yes — if you can’t wait for the EC2 Fleet Request quota increase, there are a couple of workarounds you can try:


✅ Option 1: Use Self-Managed Node Group (EC2 + Launch Template + ASG)

Instead of EKS-managed node groups, you can:

    Manually create EC2 instances using a Launch Template and Auto Scaling Group

    Join them to the cluster using the EKS bootstrap script

This avoids using the Fleet API, but:

    It's more work to manage updates and scaling.

    Not ideal unless you're comfortable managing infrastructure manually.


✅ Option 2: Use a Single Instance (for Testing)

If you're just testing or experimenting, you can:

    Launch a single EC2 instance manually in one of your private subnets.

    Install the EKS bootstrap tools (eksctl, awscli, kubectl)

    Manually join the node to the EKS cluster using:



    /etc/eks/bootstrap.sh my-eks-cluster

This bypasses node group provisioning completely.

✅ Option 3: Use eksctl Instead of Terraform (for Simpler Setup)

eksctl often avoids Fleet quota issues by:

    Using CloudFormation, not EC2 Fleet API directly

    Being optimized for default AWS settings

Example:

eksctl create cluster \
  --name my-eks-cluster \
  --version 1.29 \
  --region ap-south-2 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed



This may succeed where Terraform fails, depending on how AWS handles Fleet limits behind the scenes.


✅ Option 4: Change Node Group to Use Spot Instances (Not Always Reliable)

You can try this:


capacity_type = "SPOT"


But ⚠️ Spot instances still use Fleet under the hood, and this may not help if your quota is 0.


❌ What Doesn’t Work

    Changing instance type (e.g., from t3.medium to t3.large) won’t help if the problem is the Fleet API quota.

    Creating more subnets or changing AZs won’t fix this issue either.


💡 Recommendation

If you’re serious about using EKS:

    Request the quota increase ASAP

    In the meantime, try using eksctl for quick setup or deploy a test EC2 node manually


Would you like a full example of how to manually join an EC2 instance 
to EKS, or convert your Terraform to use a Launch Template workaround?

======================================================================================================================
======================================================================================================================
======================================================================================================================


To use Self-Managed Node Groups (i.e., EC2 instances via Auto Scaling Group and Launch Template) instead of EKS Managed Node Groups, you will need to:
✅ Steps Overview:

    Create Launch Template (for EC2 config)

    Create Auto Scaling Group (across private subnets)

    Join EC2 nodes to EKS cluster using the bootstrap script

    Tag the ASG and EC2 instances so EKS recognizes them

    Attach IAM role with necessary permissions

    Add required security group and permissions

    Install AWS-auth ConfigMap to allow the EC2 role to join the cluster

🛠️ Terraform Changes
1. Create a Security Group for Worker Nodes

resource "aws_security_group" "eks_worker_sg" {
  name        = "eks-worker-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-worker-sg"
  }
}


2. Create a Launch Template


resource "aws_launch_template" "eks_launch_template" {
  name_prefix   = "eks-self-managed-"
  image_id      = data.aws_ami.eks_worker_ami.id
  instance_type = "t3.xlarge"

  iam_instance_profile {
    name = aws_iam_instance_profile.eks_node_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.eks_worker_sg.id]
  }

  user_data = base64encode(templatefile("bootstrap.sh.tpl", {
    cluster_name = aws_eks_cluster.eks_cluster.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-self-managed-node"
    }
  }
}


Note: bootstrap.sh.tpl contains:

#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${cluster_name} --kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=normal'


3. Fetch EKS AMI


data "aws_ami" "eks_worker_ami" {
  owners      = ["602401143452"] # Amazon EKS AMI owner ID
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.29-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}



4. Create IAM Instance Profile


resource "aws_iam_instance_profile" "eks_node_instance_profile" {
  name = "eks-node-instance-profile"
  role = aws_iam_role.eks_node_role.name
}


5. Create Auto Scaling Group

resource "aws_autoscaling_group" "eks_asg" {
  name                      = "eks-asg"
  desired_capacity          = 2
  max_size                  = 3
  min_size                  = 1
  vpc_zone_identifier       = aws_subnet.private[*].id
  launch_template {
    id      = aws_launch_template.eks_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "kubernetes.io/cluster/${aws_eks_cluster.eks_cluster.name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "eks-self-managed-node"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}



6. Update aws-auth ConfigMap (manually or via Terraform)

This allows your EC2 nodes to join the cluster:


mapRoles:
- rolearn: arn:aws:iam::<account_id>:role/eksNodeGroupRole
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes


mapRoles:
- rolearn: arn:aws:iam::<account_id>:role/eksNodeGroupRole
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes


You can manage this with Terraform using a kubernetes_config_map or by kubectl apply from your local machine.



🧹 Remove This:


resource "aws_eks_node_group" "node_group" {
  # DELETE THIS BLOCK
}

✅ Summary

You’ve now replaced the EKS Managed Node Group with:

    Launch Template

    Auto Scaling Group

    Bootstrap script

    IAM role and instance profile

Let me know if you'd like help generating the bootstrap.sh.tpl or managing aws-auth automatically via Terraform.


Here's everything you need to:


✅ 1. Create bootstrap.sh.tpl Template File

This will be used in the user_data of the launch template to join EC2 instances to the EKS cluster.

Create a file named bootstrap.sh.tpl in your Terraform project directory with the following content:


#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${cluster_name} --kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=normal'


✅ 2. Automatically Apply aws-auth ConfigMap Using Terraform

To automate the ConfigMap update, add the following:
a. Install the Terraform Kubernetes Provider

Add this to your terraform block (at the top of your file):


provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}


b. Add the Data Source to Fetch EKS Auth Token

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.eks_cluster.name
}


c. Create aws-auth ConfigMap for Self-Managed Nodes


resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

📝 Important Notes

    Make sure you run terraform apply with credentials that have access to both AWS and the 
    Kubernetes API, or use kubectl separately for the ConfigMap if needed.

    You can verify the nodes join the cluster using:

    

    kubectl get nodes

To package all of this into a clean .tf module structure for easy reuse.
=======================================================================
=======================================================================

 — below is a modular Terraform structure to manage your EKS self-managed node group cleanly and reuse it in different environments. The setup is broken into:

 📁 Directory Structure

 eks-cluster/
├── main.tf
├── variables.tf
├── outputs.tf
├── bootstrap.sh.tpl
└── modules/
    └── self_managed_node_group/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf


🧠 Parent Module (eks-cluster/main.tf)

Here’s how you call the self-managed node group module:


module "self_managed_node_group" {
  source              = "./modules/self_managed_node_group"
  cluster_name        = aws_eks_cluster.eks_cluster.name
  cluster_endpoint    = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_data     = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  private_subnet_ids  = aws_subnet.private[*].id
  node_role_arn       = aws_iam_role.eks_node_role.arn
  instance_profile_id = aws_iam_instance_profile.eks_node_instance_profile.name
  security_group_ids  = [aws_security_group.eks_worker_sg.id]
}


Make sure bootstrap.sh.tpl is in the same eks-cluster directory.


🧩 Module: modules/self_managed_node_group/main.tf


resource "aws_launch_template" "eks" {
  name_prefix   = "eks-self-managed-"
  image_id      = data.aws_ami.eks_worker_ami.id
  instance_type = "t3.xlarge"

  iam_instance_profile {
    name = var.instance_profile_id
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_group_ids
  }

  user_data = base64encode(templatefile("${path.module}/../../bootstrap.sh.tpl", {
    cluster_name = var.cluster_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-self-managed-node"
    }
  }
}

resource "aws_autoscaling_group" "eks" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.eks.id
    version = "$Latest"
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "eks-self-managed-node"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "eks_worker_ami" {
  owners      = ["602401143452"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.k8s_version}-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = var.node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])
  }

  depends_on = [aws_autoscaling_group.eks]
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_data)
  token                  = data.aws_eks_cluster_auth.token.token
}

data "aws_eks_cluster_auth" "token" {
  name = var.cluster_name
}



modules/self_managed_node_group/variables.tf



variable "cluster_name" {}
variable "cluster_endpoint" {}
variable "cluster_ca_data" {}
variable "private_subnet_ids" {
  type = list(string)
}
variable "node_role_arn" {}
variable "instance_profile_id" {}
variable "security_group_ids" {
  type = list(string)
}
variable "k8s_version" {
  default = "1.29"
}



modules/self_managed_node_group/outputs.tf


✅ Final Step: Run Terraform

From the root eks-cluster/ directory:


terraform init
terraform apply




Note:

<img width="1366" height="768" alt="Screenshot (7)" src="https://github.com/user-attachments/assets/ca5984b0-d6cc-4dd7-9e52-d0eee793fe1e" />







    



    










