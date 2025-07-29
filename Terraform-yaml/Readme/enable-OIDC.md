To enable OIDC (OpenID Connect) for an Amazon EKS cluster using eksctl, you typically want to associate an OIDC provider with your EKS cluster to allow IAM roles for service accounts (IRSA). This setup lets Kubernetes workloads securely access AWS services using fine-grained permissions.

Here's how you can enable OIDC for an EKS cluster using eksctl:

✅ Prerequisites
eksctl installed: Installation guide

AWS CLI configured with appropriate permissions

Existing EKS cluster (or use eksctl to create one)

🛠️ Step-by-Step: Enable OIDC with eksctl
1. Associate OIDC Provider
Run the following command to associate an OIDC provider with your existing EKS cluster:



eksctl utils associate-iam-oidc-provider \
  --region <region> \
  --cluster <cluster-name> \
  --approve

Example:

eksctl utils associate-iam-oidc-provider \
  --region us-west-2 \
  --cluster my-eks-cluster \
  --approve

🔍 This will set up an IAM OIDC identity provider for your EKS cluster. The --approve flag skips the confirmation prompt.



2. Verify OIDC Provider
You can verify the OIDC provider with:


✅ Next Steps (Optional but Common)
After enabling OIDC, you're ready to:

Create IAM roles for service accounts (IRSA) using eksctl

Use Kubernetes service accounts to securely access AWS services (e.g., S3, DynamoDB, etc.)

Example command to create a service account with an IAM role:

eksctl create iamserviceaccount \
  --name my-service-account \
  --namespace default \
  --cluster my-eks-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve \
  --override-existing-serviceaccounts



============================================================================================================
============================================================================================================

To enable OIDC (OpenID Connect) using the AWS CLI for use with services like EKS (Elastic Kubernetes Service), you typically follow these steps:



✅ Step-by-Step: Enable OIDC for an EKS Cluster Using AWS CLI
1. Get the EKS Cluster Name and Region
Make sure you know your EKS cluster name and region.

CLUSTER_NAME=my-cluster
REGION=us-west-2

2. Check if OIDC is Already Enabled

aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text

If this returns a URL (starting with https://oidc.eks...), OIDC is already enabled.

If it returns None, continue.

3. Associate OIDC Provider

eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve


✅ eksctl is recommended for this part as AWS CLI alone does not support creating the IAM OIDC provider with automatic trust policy generation. If you must use raw AWS CLI, you can manually create the provider (see below).



⚠️ Alternative: Manually Create OIDC Provider (Using AWS CLI Only)
A. Get OIDC URL

OIDC_URL=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text)


B. Get OIDC Certificate Thumbprint
You need the certificate thumbprint of the OIDC provider's TLS cert:

echo | openssl s_client -servername $(echo $OIDC_URL | cut -d/ -f3) -showcerts 2>/dev/null | \
  openssl x509 -fingerprint -noout | \
  cut -d'=' -f2 | sed 's/://g' > thumbprint.txt

THUMBPRINT=$(cat thumbprint.txt)


C. Create the IAM OIDC Identity Provider

aws iam create-open-id-connect-provider \
  --url $OIDC_URL \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list $THUMBPRINT

✅ Verification

aws iam list-open-id-connect-providers

You should see your new OIDC provider listed.

Would you like help with configuring IAM roles for service accounts after enabling OIDC (e.g. for IRSA)?


=============================================================================================================
=============================================================================================================

automates several steps that you can also perform manually using the AWS CLI. Here's how to replicate this manually using only the AWS CLI:


🔁 Equivalent AWS CLI Steps to Associate OIDC Provider
✅ 1. Get the OIDC issuer URL

aws eks describe-cluster \
  --name my-eks-cluster \
  --region us-west-2 \
  --query "cluster.identity.oidc.issuer" \
  --output text


Save the output — it will look like:

https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E


Let’s call this $OIDC_PROVIDER_URL.



✅ 2. Get your AWS account ID


aws sts get-caller-identity --query Account --output text


✅ 3. Create the OIDC identity provider (if not already existing)
To do this manually, you must:

Extract the thumbprint for the certificate (Amazon uses 9e99a48a9960b14926bb7f3b02e22da0afd10df6)

Construct the create-open-id-connect-provider command

aws iam create-open-id-connect-provider \
  --url https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da0afd10df6


Replace the URL with your actual OIDC issuer URL from step 1.



✅ Verify OIDC Provider was Created


aws iam list-open-id-connect-providers


You should see an ARN like:

arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E


✅ Summary
While eksctl automates all of this (especially setting the thumbprint and checking for duplicates), the manual AWS CLI flow involves:

Describing the EKS cluster

Creating an OIDC provider in IAM with that info

Would you like a script that automates this process using AWS CLI and bash?










==============================================================================================
==============================================================================================


To enable OIDC (OpenID Connect) for an Amazon EKS cluster using AWS CLI, you need to:

Retrieve the OIDC issuer URL from your EKS cluster.

Create an IAM OIDC identity provider using that URL.

This allows you to use IAM roles for service accounts (IRSA) in EKS.

✅ Step-by-Step: Enable OIDC with AWS CLI
🔹 Step 1: Set Variables


REGION="us-west-2"
CLUSTER_NAME="my-eks-cluster"



🔹 Step 2: Get the OIDC Issuer URL

OIDC_URL=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.identity.oidc.issuer" \
  --output text)


Check the value:

echo $OIDC_URL


🔹 Step 3: Get Your AWS Account ID

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)



🔹 Step 4: Create the IAM OIDC Provider
You must extract the hostpath (strip https://) from the OIDC URL:

OIDC_HOSTPATH=$(echo $OIDC_URL | sed 's/^https:\/\///')


Now create the IAM OIDC provider:

aws iam create-open-id-connect-provider \
  --url "$OIDC_URL" \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da0afd10df6


✅ The thumbprint 9e99a48a9960b14926bb7f3b02e22da0afd10df6 is standard for the EKS public OIDC endpoint.

🔹 Step 5: Verify the OIDC Provider Was Created

aws iam list-open-id-connect-providers


Look for an entry like:

arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<id>


✅ OIDC Is Now Enabled!
You can now create IAM roles for service accounts (IRSA) in your EKS cluster.

Would you like help creating an IAM role for a Kubernetes service account using this OIDC provider?




========================================================================================
========================================================================================

 — here’s the simplest equivalent of that eksctl command using only AWS CLI:


✅ Minimal AWS CLI Equivalent

CLUSTER_NAME="my-eks-cluster"
REGION="us-west-2"

OIDC_URL=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text)

aws iam create-open-id-connect-provider \
  --url "$OIDC_URL" \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da0afd10df6


✅ This does the same thing as:

eksctl utils associate-iam-oidc-provider \
  --region us-west-2 \
  --cluster my-eks-cluster \
  --approve

But manually using AWS CLI only.
