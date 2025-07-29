If you're looking to get OIDC set up for Amazon EKS (Elastic Kubernetes Service), the context is typically to enable Kubernetes workloads to securely access AWS services using IAM roles — without managing long-lived AWS credentials. This is achieved by integrating OIDC with IAM roles for service accounts (IRSA).

✅ Steps to Enable OIDC on EKS (IRSA)
🔹 1. Check if OIDC Provider Is Enabled for Your EKS Cluster


aws eks describe-cluster --name <your-cluster-name> --query "cluster.identity.oidc.issuer" --output text


If it returns an OIDC URL like https://oidc.eks.<region>.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E, you're good.

If not, you need to enable it:



Associate an OIDC Provider With Your EKS Cluster


eksctl utils associate-iam-oidc-provider \
  --region <your-region> \
  --cluster <your-cluster-name> \
  --approve


This creates an OIDC identity provider in IAM tied to your EKS cluster.

🔹 3. Create an IAM Role for a Kubernetes Service Account
This lets pods in your cluster assume the IAM role via OIDC.

Use eksctl to create the IAM role and map it to a service account:

eksctl create iamserviceaccount \
  --name <sa-name> \
  --namespace <namespace> \
  --cluster <cluster-name> \
  --attach-policy-arn arn:aws:iam::<account-id>:policy/<your-policy> \
  --approve \
  --override-existing-serviceaccounts

This does 3 things:

Creates a Kubernetes service account

Creates an IAM role with a trust policy for your EKS OIDC provider

Annotates the service account so pods using it will assume the IAM role


🔹 4. Use the Service Account in Your Pod
In your pod/deployment YAML:


spec:
  serviceAccountName: <sa-name>

This ensures the pod uses the IAM role with the permissions attached.

 5. IAM Policy Example (e.g., access to S3)


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::my-bucket/*"]
    }
  ]
}


🧩 Summary
Component	Purpose
OIDC Provider	Lets EKS issue identity tokens to pods
IAM Role	Grants access to AWS services
Kubernetes Service Account	Links pod identity to IAM role via OIDC

If you're using Terraform, Helm, or need help with a specific setup (e.g., Fluent Bit, Karpenter, external-dns), I can guide you through that too.

Would you like a full example using eksctl, Terraform, or raw YAML?


