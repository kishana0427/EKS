eksctl utils associate-iam-oidc-provider \
  --region ap-south-1 \
  --cluster my-eks-cluster \
  --approve


#eksctl utils associate-iam-oidc-provider \
#  --region <region> \
#  --cluster <cluster-name> \
#  --approve


##################### OR #################

# ✅ Minimal AWS CLI Equivalent


#CLUSTER_NAME="my-eks-cluster"
#REGION="ap-south-1"

#OIDC_URL=$(aws eks describe-cluster \
#  --name $CLUSTER_NAME \
#  --region $REGION \
#  --query "cluster.identity.oidc.issuer" \
#  --output text)

#aws iam create-open-id-connect-provider \
#  --url "$OIDC_URL" \
#  --client-id-list sts.amazonaws.com \
#  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da0afd10df6

