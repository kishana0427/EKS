






#Create the policy:



aws iam create-policy \
  --policy-name AmazonEKSClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json



3. Install Cluster Autoscaler using Helm

Add Helm repo:



helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update



Install:


helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=<your-cluster-name> \
  --set awsRegion=<your-region> \
  --set cloudProvider=aws \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.expander=least-waste \
  --set extraArgs.scan-interval=10s \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<IRSA-role-arn>



Replace:

    <your-cluster-name> (e.g., eks-prod-cluster)

    <your-region> (e.g., us-west-2)

    <IRSA-role-arn> (the ARN of the IAM role Terraform created)





4. Verify Installation

Check pods:


kubectl get pods -n kube-system -l "app.kubernetes.io/name=cluster-autoscaler"



Check logs:


kubectl logs -n kube-system -l "app.kubernetes.io/name=cluster-autoscaler"



You should see log entries like:



scale up group eks-node-group from 2 to 3


🛡️ Best Practices for Production

    Pin a specific Helm chart version for reproducibility.

    Use priorityClassName: system-cluster-critical for critical workloads.

    Consider monitoring autoscaler metrics via Prometheus or CloudWatch.


Would you like a ready-to-run Helm command with variables filled in based on your Terraform output?


Below is a ready-to-run Helm install command tailored to your EKS setup. It assumes:

    Cluster name: eks-prod-cluster

    AWS region: us-west-2

    IRSA role was created via Terraform and outputted as module.cluster_autoscaler_irsa.iam_role_arn


✅ Step 1: Extract the IRSA Role ARN from Terraform (if not known)

Run this:


terraform output -raw cluster_autoscaler_iam_role_arn


Let’s say it returns:


arn:aws:iam::123456789012:role/eks-cluster-autoscaler-irsa



✅ Step 2: Final Helm Command

Now run the following command (replace the ARN if needed):


helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=eks-prod-cluster \
  --set awsRegion=us-west-2 \
  --set cloudProvider=aws \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::123456789012:role/eks-cluster-autoscaler-irsa" \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.expander=least-waste \
  --set extraArgs.scan-interval=10s


📌 Verify After Deployment


kubectl get pods -n kube-system -l "app.kubernetes.io/name=cluster-autoscaler"
kubectl logs -n kube-system -l "app.kubernetes.io/name=cluster-autoscaler"



You should see the autoscaler watching your managed node group and scaling nodes up/down based on pod demand.

Would you like to pin the Helm chart version or configure CloudWatch metrics for autoscaler next?


— let's do both:
✅ 1. Pin the Helm Chart Version

Pinning ensures repeatable deployments and protects against unexpected breaking changes when the chart updates.
🔍 Find Available Versions


helm search repo autoscaler/cluster-autoscaler --versions


For example, you might see:


NAME                               CHART VERSION   APP VERSION
autoscaler/cluster-autoscaler      9.34.0          1.29.2
autoscaler/cluster-autoscaler      9.33.0          1.28.2
...


Pick the version that matches your EKS version (you’re using 1.29). We'll use 9.34.0.


📦 Updated Helm Command with Chart Version


helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --version 9.34.0 \
  --namespace kube-system \
  --set autoDiscovery.clusterName=eks-prod-cluster \
  --set awsRegion=us-west-2 \
  --set cloudProvider=aws \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::123456789012:role/eks-cluster-autoscaler-irsa" \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.expander=least-waste \
  --set extraArgs.scan-interval=10s


✅ 2. Enable CloudWatch Logging for Cluster Autoscaler

Cluster Autoscaler logs to standard output. To forward them to CloudWatch:
Option A: Use fluent-bit or aws-for-fluent-bit DaemonSet

    Deploy aws-for-fluent-bit from AWS Helm chart:


helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm upgrade --install aws-fluent-bit fluent/fluent-bit \
  --namespace kube-system \
  --set cloudWatch.enabled=true \
  --set cloudWatch.logGroupName=/aws/eks/eks-prod-cluster/cluster-autoscaler \
  --set cloudWatch.region=us-west-2 \
  --set awsRegion=us-west-2 \
  --set serviceAccount.create=true \
  --set serviceAccount.name=fluent-bit-sa




Verify CloudWatch log group:
Go to CloudWatch Logs → /aws/eks/eks-prod-cluster/cluster-autoscaler

(Optional) Restrict the filter to just the cluster-autoscaler pods by customizing Fluent Bit config.


Option B: Use EKS Control Plane Logging

This doesn't capture autoscaler logs (which run on nodes), but it's useful for API audit logs. Let me know if you want that enabled too.


✅ Summary
Feature	Configured
Cluster Autoscaler	✅ via Helm
Version pinned	✅ 9.34.0
IRSA for IAM	✅ via Terraform
CloudWatch Logs	✅ via FluentBit




Would you like me to generate a values.yaml file for Helm instead of inline flags, or help you configure Fluent Bit further to capture only autoscaler logs?

— let’s generate a clean, production-ready values.yaml file for Cluster Autoscaler using Helm, and also outline how to configure Fluent Bit to only forward Cluster Autoscaler logs to CloudWatch.


✅ values.yaml for Cluster Autoscaler

This YAML file replaces all the CLI --set flags you used earlier. Save it as:
📄 cluster-autoscaler-values.yaml


autoDiscovery:
  clusterName: eks-prod-cluster

awsRegion: us-west-2
cloudProvider: aws

rbac:
  serviceAccount:
    create: false
    name: cluster-autoscaler

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eks-cluster-autoscaler-irsa

extraArgs:
  balance-similar-node-groups: "true"
  skip-nodes-with-system-pods: "false"
  expander: least-waste
  scan-interval: 10s

resources:
  limits:
    cpu: 100m
    memory: 300Mi
  requests:
    cpu: 50m
    memory: 200Mi

priorityClassName: system-cluster-critical

nodeSelector:
  eks.amazonaws.com/capacityType: ON_DEMAND

tolerations:
  - key: "CriticalAddonsOnly"
    operator: "Exists"
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"



Note: Replace the IAM Role ARN under serviceAccount.annotations with your actual ARN if it differs.




🔧 Helm install using this file:


helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --version 9.34.0 \
  --namespace kube-system \
  -f cluster-autoscaler-values.yaml



✅ Fluent Bit for Logging Autoscaler Only

Here’s how to limit logging to only the Cluster Autoscaler pod logs using aws-for-fluent-bit.
📄 fluent-bit-values.yaml


cloudWatch:
  enabled: true
  logGroupName: /aws/eks/eks-prod-cluster/cluster-autoscaler
  logStreamPrefix: autoscaler-
  region: us-west-2

awsRegion: us-west-2

serviceAccount:
  create: true
  name: fluent-bit-sa

filter:
  enabled: true
  match: kube.*
  # Only include cluster-autoscaler logs
  customPlugin: |
    [FILTER]
        Name          grep
        Match         kube.*
        Regex         container_name  cluster-autoscaler



This sets up a grep filter that only allows logs from pods with container_name matching cluster-autoscaler.


🔧 Install Fluent Bit with this filter:


helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm upgrade --install aws-fluent-bit fluent/fluent-bit \
  --namespace kube-system \
  -f fluent-bit-values.yaml



🔍 Verification Steps

    Autoscaler logs in CloudWatch:
    Go to AWS Console → CloudWatch Logs → /aws/eks/eks-prod-cluster/cluster-autoscaler

    Confirm log source:
    You should only see logs from the cluster-autoscaler container.

    Confirm pod:


kubectl get pods -n kube-system -l app.kubernetes.io/name=cluster-autoscaler




