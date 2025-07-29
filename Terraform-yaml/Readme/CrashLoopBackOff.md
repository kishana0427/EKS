kubectl get pods -n kube-system                      NAME                                                     READY   STATUS             RESTARTS        AGE
aws-node-7sfkq                                           2/2     Running            0               10m
aws-node-hlc55                                           2/2     Running            0               10m
cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-lxs2b   0/1     CrashLoopBackOff   6 (3m15s ago)   11m
coredns-6c55b85fbb-s7pmn                                 1/1     Running            0               12m
coredns-6c55b85fbb-xsvsr                                 1/1     Running            0               12m
kube-proxy-fvhcp                                         1/1     Running            0               10m
kube-proxy-wnm4v                                         1/1     Running            0               10m





The cluster-autoscaler pod is crashing repeatedly and stuck in a CrashLoopBackOff state:


cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-lxs2b   0/1   CrashLoopBackOff   6 (3m15s ago)   11m



This means the pod starts, fails, and then Kubernetes retries starting it, but the issue persists. Here's how to troubleshoot and potentially fix it:
🔍 Step 1: Get Logs from the Pod

Run the following command to get the logs from the autoscaler pod:


kubectl logs -n kube-system cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-lxs2b


This will likely reveal the root cause—common issues include:

    Incorrect AWS IAM permissions

    Misconfigured flags or environment variables

    Unrecognized node group settings

    AWS region mismatch

 kubectl logs -n kube-system cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-wgx5g


I0725 05:40:50.396261       1 auto_scaling_groups.go:367] Regenerating instance to ASG map for ASG names: []
I0725 05:40:50.396274       1 auto_scaling_groups.go:374] Regenerating instance to ASG map for ASG tags: map[k8s.io/cluster-autoscaler/enabled: k8s.io/cluster-autoscaler/my-eks-cluster:]
E0725 05:40:53.518146       1 aws_manager.go:125] Failed to regenerate ASG cache: NoCredentialProviders: no valid providers in chain. Deprecated.
        For verbose messaging see aws.Config.CredentialsChainVerboseErrors
F0725 05:40:53.518171       1 aws_cloud_provider.go:437] Failed to create AWS Manager: NoCredentialProviders: no valid providers in chain. Deprecated.
        For verbose messaging see aws.Config.CredentialsChainVerboseErrors


That log message nails it:
❌ Error:


Failed to create AWS Manager: NoCredentialProviders: no valid providers in chain


🔍 What It Means:

The Cluster Autoscaler pod cannot find AWS credentials — so it can't call the Auto Scaling API to discover node groups or scale them.

✅ Solution Options

You have two main ways to give credentials to the autoscaler in EKS:


Option 1: Use IAM Roles for Service Accounts (IRSA) — Recommended

This is the best practice for EKS.
Steps:

    ✅ Create an IAM role with the required permissions.

    Attach a trust relationship to allow EKS to assume the role:


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account_id>:oidc-provider/<your_eks_oidc_provider>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "<your_eks_oidc_provider>:sub": "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }
  ]
}



✅ Attach permissions to this IAM role:


Example policy:



{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeInstanceTypes"
      ],
      "Resource": "*"
    }
  ]
}



✅ Update your cluster-autoscaler manifest to use the IRSA role by adding an annotation


serviceAccount:
  name: cluster-autoscaler
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account_id>:role/<your-irsa-role-name>


✅ Make sure you created the service account in kube-system namespace:


kubectl get serviceaccount cluster-autoscaler -n kube-system


If not, create it with the IRSA annotation.


Option 2: Run the Pod on a Node with IAM Permissions

If you're not using IRSA, then:

    The node IAM role running the cluster-autoscaler pod must have permissions.

    But this is less secure and not recommended.



✅ Recommended: Use IRSA

Let me know and I’ll give you a full Terraform or YAML config to set up IRSA for Cluster Autoscaler — just say whether you’re using Helm, plain YAML, or Terraform.


all methods using Helm, plain YAML, or Terraform:
===============================================

— here are complete instructions for setting up Cluster Autoscaler with proper AWS credentials using IRSA, in all three options: Helm, plain YAML, and Terraform.


✅ Step 1: Create IAM Role for IRSA (applies to all setups)

This role allows Cluster Autoscaler to access Auto Scaling APIs securely via IRSA (IAM Roles for Service Accounts).




🔧 1.1 Get your OIDC provider URL

aws eks describe-cluster --name <your-cluster-name> --query "cluster.identity.oidc.issuer" --output text




Save this value (without the https:// prefix) — you’ll need it for the trust policy.


🔧 1.2 Create IAM Role for Cluster Autoscaler
🚀 Use AWS CLI:

Replace the values before running:



CLUSTER_NAME="my-eks-cluster"
NAMESPACE="kube-system"
SERVICE_ACCOUNT_NAME="cluster-autoscaler"
OIDC_PROVIDER="oidc.eks.<region>.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"

# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}"
        }
      }
    }
  ]
}
EOF





# Create role
aws iam create-role \
  --role-name cluster-autoscaler-irsa-role \
  --assume-role-policy-document file://trust-policy.json





🛡️ Attach the required permissions:



aws iam attach-role-policy \
  --role-name cluster-autoscaler-irsa-role \
  --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess



Or use a least-privilege custom policy (optional — ask if you want it).



✅ Step 2: Deploy Cluster Autoscaler


🚀 Option 1: Helm

Add the chart repo and install with IRSA annotations:


helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update


helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-eks-cluster \
  --set awsRegion=ap-south-1 \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::<account-id>:role/cluster-autoscaler-irsa-role \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-local-storage=false \
  --set extraArgs.expander=least-waste






🚀 Option 2: Plain YAML

    Create the Service Account:


apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/cluster-autoscaler-irsa-role



Apply:


kubectl apply -f service-account.yaml



    Deploy Cluster Autoscaler:

Download the manifest and modify:


curl -O https://raw.githubusercontent.com/kubernetes/autoscaler/cluster-autoscaler-1.27.1/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml



Edit:

    Add your --node-group-auto-discovery flags

    Set --cloud-provider=aws

    Set your cluster-name

    Add the service account: cluster-autoscaler

    Set image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.27.1

Then apply:


kubectl apply -f cluster-autoscaler-autodiscover.yaml




🚀 Option 3: Terraform
Step 1: Create IAM Role with terraform


resource "aws_iam_role" "cluster_autoscaler" {
  name = "cluster-autoscaler-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler_policy" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}




Step 2: Create the Service Account with the Role


resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
}


Then deploy the Helm chart (via Terraform or manually) referencing this IRSA role.



✅ Verification

Run:


kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler


You should see:


Cluster Autoscaler initialized
AWS cloud provider initialized


No more NoCredentialProviders error!


Would you like a full working Terraform module or Helm values.yaml example?


Give me for all:
==============

To give you the complete setup for all deployment methods, I’ve compiled detailed working examples for:


✅ 1. Helm: values.yaml

Create a file named values.yaml:


autoDiscovery:
  clusterName: my-eks-cluster

awsRegion: ap-south-1

rbac:
  serviceAccount:
    create: true
    name: cluster-autoscaler
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/cluster-autoscaler-irsa-role

extraArgs:
  cloud-provider: aws
  balance-similar-node-groups: "true"
  skip-nodes-with-local-storage: "false"
  expander: least-waste
  node-group-auto-discovery: asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/my-eks-cluster

image:
  tag: v1.27.1



Install with:


helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update



helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system -f values.yaml




✅ 2. Plain YAML: Full Manifest
ServiceAccount:


apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/cluster-autoscaler-irsa-role


Cluster Autoscaler Deployment:


apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - name: cluster-autoscaler
          image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.27.1
          command:
            - ./cluster-autoscaler
            - --cloud-provider=aws
            - --balance-similar-node-groups
            - --skip-nodes-with-local-storage=false
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/my-eks-cluster
            - --expander=least-waste
            - --cluster-name=my-eks-cluster
          resources:
            limits:
              cpu: 100m
              memory: 300Mi
            requests:
              cpu: 100m
              memory: 300Mi




Apply both files:


kubectl apply -f serviceaccount.yaml
kubectl apply -f cluster-autoscaler.yaml


✅ 3. Terraform: Full IRSA Setup
IAM Role and Policy:



data "aws_eks_cluster" "cluster" {
  name = "my-eks-cluster"
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.aws_eks_cluster.cluster.name
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "cluster-autoscaler-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}




Kubernetes Service Account (via Terraform):


provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
}




You can deploy the Helm chart using helm_release from Terraform if desired, or run Helm manually using this service account.




Let me know if you’d like:

    A complete Terraform module

    Integration with helm_release in Terraform

    Or a way to test if the IRSA connection is working after setup

I'm happy to tailor it to your workflow!


yes give me all
==============


I've prepared a complete setup covering Terraform, Helm, and plain YAML for deploying Cluster Autoscaler with IRSA. To view and edit this setup in a collaborative coding environment (ChatGPT canvas), you'll need to log in to ChatGPT.

Once you're logged in, I can walk you through:

    ✅ Terraform module for:

        Creating the IAM role and policy

        Configuring the Kubernetes service account

        Optionally deploying the Helm release

    ✅ Helm values.yaml for installing Cluster Autoscaler with the correct settings

    ✅ Plain YAML manifests for manual deployments (ServiceAccount + Deployment)

Would you like me to bundle this into a downloadable zip or paste the Terraform module and Helm release block directly here?









🔍 Step 2: Describe the Pod


 kubectl logs -n kube-system cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-wgx5g






Check for issues in pod scheduling or initialization:


kubectl describe pod -n kube-system cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-lxs2b

Look under:

    Events: for errors like ImagePullBackOff, PermissionDenied, etc.

    Containers: for termination reasons and exit codes.

🛠️ Common Fixes

    Check IAM Role Permissions:
    Ensure the IAM role assigned to the node or service account running the cluster-autoscaler has the required permissions, such as:

        autoscaling:DescribeAutoScalingGroups

        autoscaling:SetDesiredCapacity

        autoscaling:DescribeLaunchConfigurations

        autoscaling:TerminateInstanceInAutoScalingGroup

    Correct CLI Flags:
    Confirm the deployment contains correct flags like:


- --cloud-provider=aws
- --nodes=MIN:MAX:ASG_NAME
- --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<CLUSTER_NAME>


    Match Region & Cluster Name:
    Make sure the cluster-autoscaler is deployed with the correct AWS region and cluster name.

Would you like me to help interpret the logs once you run the kubectl logs command? You can paste them here.



kubectl logs -n kube-system cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-lxs2b

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
I0725 04:51:04.313228       1 auto_scaling_groups.go:367] Regenerating instance to ASG map for ASG names: []
I0725 04:51:04.313242       1 auto_scaling_groups.go:374] Regenerating instance to ASG map for ASG tags: map[k8s.io/cluster-autoscaler/enabled: k8s.io/cluster-autoscaler/my-eks-cluster:]


the logs snippet — here's what it's telling us:
🔍 Log Analysis

I0725 04:51:04.313228       1 auto_scaling_groups.go:367] Regenerating instance to ASG map for ASG names: []
I0725 04:51:04.313242       1 auto_scaling_groups.go:374] Regenerating instance to ASG map for ASG tags: map[k8s.io/cluster-autoscaler/enabled: k8s.io/cluster-autoscaler/my-eks-cluster:]


This log confirms that the cluster-autoscaler is running in "auto-discovery" mode, using the following tags to find AWS Auto Scaling Groups (ASGs):

    k8s.io/cluster-autoscaler/enabled

    k8s.io/cluster-autoscaler/my-eks-cluster

But importantly:

SG names: [] — no ASG names are found that match the discovery criteria.


⚠️ Root Cause

Cluster-autoscaler is unable to find any Auto Scaling Groups because the required tags are likely missing on your ASGs in AWS.

✅ Fix: Add Tags to Your ASGs

Go to the EC2 > Auto Scaling Groups section in the AWS console, and ensure that each ASG backing your EKS node groups has the following two tags:


| Key                                        | Value                                |
| ------------------------------------------ | ------------------------------------ |
| `k8s.io/cluster-autoscaler/enabled`        | `true`                               |
| `k8s.io/cluster-autoscaler/<CLUSTER_NAME>` | `owned` (or any value, e.g., `true`) |




In your case:


| Key                                        | Value  |
| ------------------------------------------ | ------ |
| `k8s.io/cluster-autoscaler/enabled`        | `true` |
| `k8s.io/cluster-autoscaler/my-eks-cluster` | `true` |


Be sure to check "Propagate at launch" when adding tags via the AWS Console.

🔄 Then: Restart the Pod

After adding the tags, restart the autoscaler pod to force it to retry discovery:


kubectl delete pod -n kube-system cluster-autoscaler-aws-cluster-autoscaler-5dc6fb-lxs2b


It should come back up and find the ASGs correctly.


a quick AWS CLI command to add those tags, if you're managing things via IaC or scripts:
=======================================================================================

— here's how to add the required tags to your EKS Auto Scaling Group using the AWS CLI:


✅ Step 1: Identify Your ASG Name

If you're not sure of your ASG name, you can list them:


aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[*].AutoScalingGroupName" \
  --output table


Look for ASGs associated with your EKS node groups — their names usually contain your cluster name.


✅ Step 2: Tag the ASG

Use the following command to tag the ASG (replace <ASG_NAME> and <CLUSTER_NAME>):


aws autoscaling create-or-update-tags --tags \
  Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true,ResourceId=<ASG_NAME>,ResourceType=auto-scaling-group \
  Key=k8s.io/cluster-autoscaler/<CLUSTER_NAME>,Value=true,PropagateAtLaunch=true,ResourceId=<ASG_NAME>,ResourceType=auto-scaling-group



Example for your cluster:

aws autoscaling create-or-update-tags --tags \
  Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true,ResourceId=my-eks-nodegroup-asg,ResourceType=auto-scaling-group \
  Key=k8s.io/cluster-autoscaler/my-eks-cluster,Value=true,PropagateAtLaunch=true,ResourceId=my-eks-nodegroup-asg,ResourceType=auto-scaling-group


Replace my-eks-nodegroup-asg with your actual ASG name.

🔁 Step 3: Restart the Cluster Autoscaler Pod


kubectl delete pod -n kube-system -l app.kubernetes.io/name=cluster-autoscaler


This will delete the crashing pod and let Kubernetes recreate it with a fresh start.


if you'd like help scripting this or integrating it with Terraform or CloudFormation:
====================================================================================

— if you're managing your EKS node groups and ASGs with Terraform, you'll want to add the required tags directly in your Terraform config, so they’re attached automatically and managed declaratively.


✅ Option 1: Using aws_eks_node_group (managed node groups)

If you're using managed node groups, add the tags under the tags and labels blocks like this:


resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "example-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  labels = {
    "k8s.io/cluster-autoscaler/enabled"       = "true"
    "k8s.io/cluster-autoscaler/my-eks-cluster" = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/enabled"       = "true"
    "k8s.io/cluster-autoscaler/my-eks-cluster" = "true"
  }
}


tags apply to the ASG, labels apply to the Kubernetes nodes. Both are important for autoscaler behavior.


✅ Option 2: Using aws_autoscaling_group (self-managed node groups)

If you're using self-managed node groups, tag the ASG resource like this:


resource "aws_autoscaling_group" "example" {
  name                 = "example-asg"
  max_size             = 4
  min_size             = 1
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = var.subnet_ids

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/my-eks-cluster"
    value               = "true"
    propagate_at_launch = true
  }
}


🔄 After Adding Tags

Once you've updated the config:

terraform apply


Then restart the cluster-autoscaler pod as before:


kubectl delete pod -n kube-system -l app.kubernetes.io/name=cluster-autoscaler


Would you like help determining which of these options you're using (managed vs. self-managed node groups)? Or do you want a full working module snippet?


managed node groups:
==================

Great question! Here's a quick rundown to help you distinguish managed vs self-managed node groups in EKS:


Managed Node Groups

    Provisioned and managed by EKS service.

    Created via AWS Console, CLI, or Terraform using the aws_eks_node_group resource.

    AWS handles lifecycle operations like rolling updates, upgrades, and node replacement.

    Automatically creates and manages the underlying Auto Scaling Groups.

    Easier to manage, recommended for most users.

    You typically interact with the aws_eks_node_group Terraform resource.

How to check:

    If your Terraform uses aws_eks_node_group, you're using managed node groups.

    On AWS Console, managed node groups appear under the EKS cluster -> “Compute” section.

Self-Managed Node Groups (aka unmanaged)

    You create and manage the nodes yourself.

    Usually use aws_launch_configuration or aws_launch_template + aws_autoscaling_group in Terraform.

    You manage the ASG lifecycle, rolling updates, and node lifecycle manually.

    Offers more flexibility/customization but requires more effort.

How to check:

    If your Terraform uses aws_autoscaling_group or aws_launch_configuration resources directly for EKS nodes, it’s a self-managed node group.

    On AWS Console, these are just plain Auto Scaling Groups not managed by EKS.



Summary Table

| Feature              | Managed Node Group   | Self-Managed Node Group                          |
| -------------------- | -------------------- | ------------------------------------------------ |
| Terraform Resource   | `aws_eks_node_group` | `aws_autoscaling_group` + Launch Config/Template |
| Lifecycle Management | Handled by EKS       | Handled by you                                   |
| Ease of Use          | Easier               | More control, more complexity                    |
| Upgrade Process      | Automatic via EKS    | Manual                                           |


If you share your Terraform code or how you provision your nodes, I can help pinpoint which one you use! Want to share it?
