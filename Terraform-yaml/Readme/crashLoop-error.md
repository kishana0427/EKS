 kubectl get pods -n kube-system -w
NAME                                  READY   STATUS    RESTARTS   AGE
aws-node-7sfkq                        2/2     Running   0          11h
aws-node-hlc55                        2/2     Running   0          11h
cluster-autoscaler-7b59689f7b-wmgkz   1/1     Running   0          22s
coredns-6c55b85fbb-s7pmn              1/1     Running   0          11h
coredns-6c55b85fbb-xsvsr              1/1     Running   0          11h
kube-proxy-fvhcp                      1/1     Running   0          11h
kube-proxy-wnm4v                      1/1     Running   0          11h
cluster-autoscaler-7b59689f7b-wmgkz   0/1     Error     0          23s
cluster-autoscaler-7b59689f7b-wmgkz   1/1     Running   1 (2s ago)   25s
cluster-autoscaler-7b59689f7b-wmgkz   0/1     Error     1 (3s ago)   26s
cluster-autoscaler-7b59689f7b-wmgkz   0/1     CrashLoopBackOff   1 (14s ago)   40s
cluster-autoscaler-7b59689f7b-wmgkz   1/1     Running            2 (16s ago)   42s
cluster-autoscaler-7b59689f7b-wmgkz   0/1     Error              2 (17s ago)   43s



kubectl logs cluster-autoscaler-7b59689f7b-wmgkz -n kube-system



WebIdentityErr: failed to retrieve credentials
caused by: InvalidIdentityToken: No OpenIDConnect provider found in your account for https://oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754



🔥 Root Cause:
Your EKS cluster does not have the IAM OIDC provider properly associated, or the IAM role used by the Cluster Autoscaler doesn't trust the OIDC provider.




✅ Fix in Steps:
Step 1: Check if OIDC provider is enabled
Run this:




aws eks describe-cluster --name <your-cluster-name> --region ap-south-1 --query "cluster.identity.oidc.issuer" --output text



Then run:


aws iam list-open-id-connect-providers | grep F9715789C8149BEC2CAA33249B0FF754



If it’s missing, you need to associate the OIDC provider.




Step 2: Create OIDC provider (if missing)
You can do it via:



eksctl utils associate-iam-oidc-provider \
  --region ap-south-1 \
  --cluster <your-cluster-name> \
  --approve




Step 3: Attach IAM Role to Cluster Autoscaler (with proper trust)
Create a policy and IAM role with the correct permissions. AWS provides an official IAM policy for Cluster Autoscaler:



curl -o cluster-autoscaler-policy.json https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/iam-policy.json
aws iam create-policy \
  --policy-name AmazonEKSClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json


Then create a service account and attach it:



eksctl create iamserviceaccount \
  --cluster=<your-cluster-name> \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::<your-account-id>:policy/AmazonEKSClusterAutoscalerPolicy \
  --approve \
  --override-existing-serviceaccounts



This will:

Create the IAM role

Associate it with the OIDC provider

Annotate the Kubernetes service account with the correct IAM role ARN


Step 4: Update or Redeploy Cluster Autoscaler
If you deployed it manually via YAML, make sure the serviceAccountName is set:


serviceAccountName: cluster-autoscaler



✅ Final Check
Once all that's done:



kubectl get pods -n kube-system
kubectl logs <cluster-autoscaler-pod> -n kube-system




You should see something like:


I0725 15:45:20.123456       1 aws_manager.go:261] Refreshed ASG list: ...




Let me know your cluster name or if you want exact commands for your setup — I can walk you through it interactively.




how to do above with aws cli:
===========================


Great — you can do the entire OIDC and IAM setup for Cluster Autoscaler using the AWS CLI, but it requires a few detailed steps.

✅ Goal:
Using AWS CLI, you will:

✅ Associate the OIDC provider

✅ Create an IAM policy for the Cluster Autoscaler

✅ Create an IAM role that trusts the EKS OIDC

✅ Annotate the Kubernetes service account

🔧 Prerequisites
Your cluster name: my-eks-cluster

Region: ap-south-1

AWS CLI installed & configured

kubectl access to the cluster


🚀 Step-by-Step using AWS CLI
Step 1: Get the OIDC issuer

CLUSTER_NAME="my-eks-cluster"
REGION="ap-south-1"

OIDC_URL=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text)

OIDC_HOST=$(echo $OIDC_URL | sed -e "s/^https:\/\///")



Step 2: Associate the OIDC provider
Check if already exists:



aws iam list-open-id-connect-providers | grep $OIDC_HOST



If missing, create it:



aws iam create-open-id-connect-provider \
  --url "$OIDC_URL" \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list "9e99a48a9960b14926bb7f3b02e22da0ecd4e4e3"




✅ Thumbprint 9e99a48a9960b14926bb7f3b02e22da0ecd4e4e3 is correct for AWS public OIDC endpoints.



Step 3: Create IAM policy for Cluster Autoscaler



curl -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/iam-policy.json

aws iam create-policy \
  --policy-name AmazonEKSClusterAutoscalerPolicy \
  --policy-document file://iam-policy.json



Save the ARN from the output — or get it again:


POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='AmazonEKSClusterAutoscalerPolicy'].Arn" \
  --output text)



Step 4: Create IAM Role for the Cluster Autoscaler



ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME="eks-cluster-autoscaler-role"
SERVICE_ACCOUNT_NAMESPACE="kube-system"
SERVICE_ACCOUNT_NAME="cluster-autoscaler"

cat <<EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/$OIDC_HOST"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "$OIDC_HOST:sub": "system:serviceaccount:$SERVICE_ACCOUNT_NAMESPACE:$SERVICE_ACCOUNT_NAME"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy.json



Step 5: Attach the IAM Policy to the Role




aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN




Step 6: Annotate the Kubernetes Service Account
Create or update the service account:


kubectl create serviceaccount $SERVICE_ACCOUNT_NAME \
  -n $SERVICE_ACCOUNT_NAMESPACE



Annotate it:


kubectl annotate serviceaccount \
  -n $SERVICE_ACCOUNT_NAMESPACE \
  $SERVICE_ACCOUNT_NAME \
  eks.amazonaws.com/role-arn=arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME



✅ Final Step: Deploy Cluster Autoscaler
Make sure your Cluster Autoscaler pod uses:



serviceAccountName: cluster-autoscaler



✅ Done!
Cluster Autoscaler now has AWS IAM permissions via IRSA (IAM Roles for Service Accounts) using only the AWS CLI.

Let me know if you want the exact Cluster Autoscaler deployment YAML next.



how to do above with yaml:
===========================



Here’s a complete and up-to-date Cluster Autoscaler deployment YAML tailored for EKS, including:

IRSA (IAM Roles for Service Accounts) integration

Autoscaler version compatible with your cluster (update if needed)

Logging and scaling config

✅ Cluster Autoscaler Deployment YAML
Save this as cluster-autoscaler.yaml and apply with kubectl apply -f cluster-autoscaler.yaml.



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
      serviceAccountName: cluster-autoscaler  # Must match IAM-bound SA
      containers:
        - name: cluster-autoscaler
          image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.29.0
          command:
            - ./cluster-autoscaler
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --balance-similar-node-groups
            - --expander=least-waste
            - --nodes=1:5:<YOUR-ASG-NAME>  # 👈 Replace this!
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<YOUR-CLUSTER-NAME>
            - --logtostderr=true
            - --stderrthreshold=info
            - --v=4
          resources:
            limits:
              cpu: 100m
              memory: 300Mi
            requests:
              cpu: 100m
              memory: 300Mi


🛠 Replace These:
<YOUR-ASG-NAME> — name of the Auto Scaling Group managed by your EKS node group

<YOUR-CLUSTER-NAME> — name of your EKS cluster (e.g., my-eks-cluster)

You can also tag your ASG instead of specifying it manually.




✅ Required ASG Tags (on your EKS node group's ASG)
Ensure your node group’s Auto Scaling Group has the following tags:

Key	Value
k8s.io/cluster-autoscaler/enabled	true
k8s.io/cluster-autoscaler/<your-cluster-name>	owned or true

Apply via console or CLI like:




aws autoscaling create-or-update-tags --tags \
  ResourceId=<your-asg-name>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
  ResourceId=<your-asg-name>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/my-eks-cluster,Value=owned,PropagateAtLaunch=true




Let me know your actual cluster name and ASG name if you want a ready-to-use version with those inserted.





