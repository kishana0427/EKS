gorizontal Pod Autoscaler (HPA) for Amazon EKS (Elastic Kubernetes Service) is used to automatically scale the number of pods in a deployment, replica set, or stateful set based on observed CPU utilization (or other select metrics).

Here’s a concise guide to setting up HPA for EKS:
✅ Prerequisites

    Amazon EKS cluster already running.

    kubectl configured to access the EKS cluster.

    Metrics Server installed.

    Your deployment should request CPU/memory resources.

🔧 Step-by-Step Setup
1. Install Metrics Server

Metrics Server is essential for HPA to gather resource metrics.


kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


Ensure it’s running:


kubectl get deployment metrics-server -n kube-system





2. Verify Deployment Has Resource Requests

HPA requires pods to have CPU (and/or memory) requests.

Example:


resources:
  requests:
    cpu: "100m"
    memory: "200Mi"
  limits:
    cpu: "200m"
    memory: "400Mi"


3. Create HPA

You can create HPA using a YAML file or kubectl directly.
Via kubectl:


kubectl autoscale deployment <deployment-name> \
  --cpu-percent=50 \
  --min=1 \
  --max=10



YAML Example:


apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50



Apply it:


kubectl apply -f hpa.yaml


4. Monitor HPA

Check the HPA status:


kubectl get hpa



See how the HPA is reacting:


kubectl describe hpa <hpa-name>


✅ Tips

    Use autoscaling/v2 for advanced metrics (e.g., memory, custom metrics, external metrics).

    Make sure CloudWatch Container Insights is enabled if you're using custom metrics from AWS.

    Combine with Cluster Autoscaler to scale EC2 nodes as pods grow.


    Would you like a full example using a sample app or custom metrics via CloudWatch?





  Let's walk through a complete example of setting up Horizontal Pod Autoscaler (HPA) with a sample app on Amazon EKS, and optionally extend it with custom metrics via CloudWatch.
🎯 Goal

    Deploy a sample app with CPU requests.

    Set up Metrics Server.

    Apply an HPA based on CPU.

    (Optional) Use custom metrics from AWS CloudWatch with HPA.

✅ Step-by-Step: Sample App + HPA (CPU-based)
Step 1: Deploy Metrics Server


kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


Patch it if you're using EKS with self-signed certificates:


kubectl patch deployment metrics-server -n kube-system \
  --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'



Step 2: Deploy a Sample App

Let’s deploy a simple NGINX app that uses CPU:


# nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        ports:
        - containerPort: 80


Apply it:


kubectl apply -f nginx-deployment.yaml


Step 3: Create HPA


kubectl autoscale deployment nginx --cpu-percent=50 --min=1 --max=10


Or use YAML:


# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50



kubectl apply -f hpa.yaml


Step 4: Test Auto-Scaling

You can simulate CPU load using a busybox pod:


kubectl run -i --tty busybox --image=busybox --restart=Never -- sh



Inside the pod, run:


while true; do wget -q -O- http://nginx; done



Monitor:


🔄 Optional: HPA with CloudWatch Custom Metrics

To scale on external metrics from AWS CloudWatch (e.g., SQS queue depth), you need:
🔹 Option 1: Use KEDA (Kubernetes Event-Driven Autoscaling)

KEDA integrates easily with CloudWatch, SQS, DynamoDB, etc.

Install via Helm:


helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --namespace keda --create-namespace


Example: scale based on SQS queue length:


apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: nginx
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>
      awsRegion: <region>
      queueLength: "5"
    authenticationRef:
      name: keda-aws-auth


You’ll also need an AWS IAM Role with permissions and a Kubernetes Secret or ServiceAccount for authentication.



✅ Summary


| Component            | Description                                  |
| -------------------- | -------------------------------------------- |
| Metrics Server       | Gathers CPU/Memory usage (required for HPA)  |
| HPA (autoscaling/v2) | Scales based on resource or custom metrics   |
| KEDA                 | For external metrics (CloudWatch, SQS, etc.) |



Would you like me to generate working manifests for the KEDA + CloudWatch case with a real AWS service (like SQS)?


Here’s a working example of how to configure KEDA on Amazon EKS to autoscale a sample deployment based on AWS SQS queue length, using either the native aws-sqs-queue scaler or the aws-cloudwatch scaler for flexibility. Both options can support scale-to-zero and integrate with HPA via KEDA.
🧩 Prerequisites

    EKS cluster with IRSA (IAM Roles for Service Accounts) enabled for KEDA

    Install KEDA via Helm with AWS role annotations

    An SQS queue in the same AWS account/region

    Sample deployment running in Kubernetes

1. Install KEDA with IAM Role (IRSA)


helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda \
  --namespace keda --create-namespace \
  --set "serviceAccount.annotations.eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/<KEDA-Operator-Role>"


This ensures the KEDA operator itself has permissions to read SQS metrics when using identityOwner: operator
Reddit+15Kedify+15Medium+15
Reddit+3KEDA+3Reddit+3
KEDA+5KEDA+5KEDA+5
.

2. Example Deployment

apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-worker
  namespace: default
spec:
  replicas: 0
  selector:
    matchLabels:
      app: my-worker
  template:
    metadata:
      labels:
        app: my-worker
    spec:
      containers:
        - name: worker
          image: my-registry/worker:latest
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"


Start with 0 replicas—KEDA will scale from zero as needed.



3A. ScaledObject Using aws-sqs-queue Scaler


apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-sqs-auth
  namespace: default
spec:
  podIdentity:
    provider: aws-eks
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: my-worker
  minReplicaCount: 0
  maxReplicaCount: 10
  pollingInterval: 30
  cooldownPeriod: 300
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: aws-sqs-auth
      metadata:
        queueURL: https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>
        queueLength: "5"
        awsRegion: "<region>"
        identityOwner: operator


Scales up when visible + in-flight messages > 5, using KEDA’s SQS scaler
Reddit+1Reddit+1
Amazon Web Services, Inc.+2KEDA+2Reddit+2
.

With identityOwner: operator, only the operator needs AWS permissions.

Uses HPA under the hood to manage replica scaling.


3B. ScaledObject Using aws-cloudwatch Scaler

apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-cw-auth
  namespace: default
spec:
  podIdentity:
    provider: aws-eks
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cw-sqs-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: my-worker
  minReplicaCount: 0
  maxReplicaCount: 10
  pollingInterval: 60
  cooldownPeriod: 300
  triggers:
    - type: aws-cloudwatch
      authenticationRef:
        name: aws-cw-auth
      metadata:
        namespace: AWS/SQS
        dimensionName: QueueName
        dimensionValue: "<queue-name>"
        metricName: ApproximateNumberOfMessagesVisible
        targetMetricValue: "10"
        awsRegion: "<region>"
        metricCollectionTime: "300"
        metricStat: "Average"
        metricStatPeriod: "300"
        identityOwner: operator



Fetches SQS length from CloudWatch and triggers scaling when queue length exceeds threshold
GitHub+1KEDA+1
.

Useful if you need CloudWatch-based filtering or cross-account solutions.

4. Monitoring and Clean-up

    Monitor scaling:

    kubectl get scaledobject -n default
kubectl get hpa
kubectl describe hpa <scaledobject-hpa-name>

To test, send messages via AWS CLI:

aws sqs send-message --queue-url https://... --message-body "job1"


Pods will scale up automatically. Once messages processed and queue empties, HPA/KEDA scale down to 0.


✅ Summary Table
Method	Source of Metric	Scales to Zero?	IAM Scope
aws-sqs-queue	Real-time SQS queue length	✅ Yes	KEDA operator (via IRSA)
aws-cloudwatch	CloudWatch SQS metric	✅ Yes	KEDA operator




📝 Notes & Tips

    Scale-to-zero is fully supported with both triggers when minReplicaCount: 0 is set.

    KEDA creates an underlying HPA for scaling. You can tune polling and cooldown intervals for smoother autoscaling behavior.

    Use identityOwner: operator to centralize AWS credentials at the operator level, avoiding per-pod credentials.

    If processing jobs can take a long time, consider ScaledJob instead of ScaledObject to better manage long-running workloads
    Reddit+12KEDA+12KEDA+12
    KEDA+5KEDA+5KEDA+5
    Reddit+13Kedify+13Reddit+13
    Reddit+8Reddit+8KEDA+8
    Medium+1Amazon Web Services, Inc.+1
    KEDA+5KEDA+5Medium+5
    .

Would you like me to tailor the manifest for ScaledJob (instead of ScaledObject), or integrate with a real app like NGINX or a consumer/producer pair similar to AWS sample?




Let’s now tailor a full working setup using KEDA's ScaledJob, which is better suited for queue-based workloads (like AWS SQS). It’s ideal for short- or long-running jobs that need to spin up pods to process items from the queue.
🎯 What We’ll Set Up

    A Kubernetes ScaledJob that:

        Pulls messages from AWS SQS

        Spins up pods to process each job

        Automatically scales based on queue length

    Includes:

        IAM + IRSA setup

        KEDA deployment

        SQS Trigger

        Job consumer pod

🧩 Requirements

    EKS cluster with IAM Roles for Service Accounts (IRSA) enabled

    An SQS queue created in your AWS account

    Helm installed

🛠️ Step-by-Step Setup
1. Create an IAM Role for KEDA Operator

Create a role with the following permissions:


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "sqs:ListQueues"
      ],
      "Resource": "*"
    }
  ]
}


Trust policy (for IRSA):


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/<OIDC_PROVIDER>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "<OIDC_PROVIDER>:sub": "system:serviceaccount:keda:keda-operator"
        }
      }
    }
  ]
}



2. Install KEDA via Helm


helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda --create-namespace \
  --set "serviceAccount.annotations.eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/<KEDA-Operator-Role>"




3. Create the Worker App

# worker-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sqs-worker
spec:
  template:
    spec:
      containers:
        - name: worker
          image: busybox
          command: ["sh", "-c", "echo Processing message && sleep 10"]
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
      restartPolicy: Never


Replace echo Processing message with your actual message processor logic (e.g., Python script that pulls and deletes from SQS).



4. Create a ScaledJob for SQS

apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-trigger-auth
  namespace: default
spec:
  podIdentity:
    provider: aws-eks
---
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: sqs-job-scaler
  namespace: default
spec:
  jobTargetRef:
    template:
      spec:
        containers:
          - name: worker
            image: busybox
            command: ["sh", "-c", "echo Processing message && sleep 10"]
            resources:
              requests:
                cpu: "100m"
                memory: "128Mi"
        restartPolicy: Never
  pollingInterval: 30
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 5
  maxReplicaCount: 5
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: aws-trigger-auth
      metadata:
        queueURL: https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>
        queueLength: "1"
        awsRegion: "<region>"
        identityOwner: operator


5. Test It

Send messages to your SQS queue:


aws sqs send-message \
  --queue-url https://sqs.<region>.amazonaws.com/<account-id>/<queue-name> \
  --message-body "Hello from EKS + KEDA"


KEDA will detect the message and start Job pods to process them.
✅ Key Differences: ScaledJob vs ScaledObject
Feature	ScaledObject	ScaledJob
Target	Deployment	Job
Best for	Web apps, services	Queue/worker jobs
Concurrency control	Limited via HPA	Native (per job)
Can scale to zero	✅ Yes	✅ Yes
Runs once per message	❌ No	✅ Yes (like Lambda)

Would you like me to:

    Provide a Python-based consumer image that actually reads from SQS?

    Help build a Helm chart or Kustomize overlay for this setup?

    Include CloudWatch Logs integration for visibility?

Let me know what direction you'd like next.




Awesome! Let’s build a complete and realistic Python-based SQS consumer, deploy it via a KEDA ScaledJob, and (optionally) integrate it with CloudWatch Logs for visibility.
✅ What We'll Build

    A Python SQS consumer Docker image that:

        Receives messages from AWS SQS

        Deletes them after processing

        Logs output (which we'll ship to CloudWatch)

    A KEDA ScaledJob to run this containerized worker

    CloudWatch Logs integration via EKS node role or sidecar (optional)

📦 Step 1: Python SQS Consumer Script

consumer.py

import boto3
import time
import os

sqs_url = os.getenv("SQS_URL")
region = os.getenv("AWS_REGION", "us-west-2")

sqs = boto3.client("sqs", region_name=region)

print(f"Listening for messages on: {sqs_url}")

def process_message(message):
    print(f"Received message: {message['Body']}")
    # Simulate processing
    time.sleep(5)

while True:
    resp = sqs.receive_message(
        QueueUrl=sqs_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=10
    )

    messages = resp.get("Messages", [])
    if not messages:
        print("No messages, exiting.")
        break

    for msg in messages:
        process_message(msg)
        sqs.delete_message(
            QueueUrl=sqs_url,
            ReceiptHandle=msg['ReceiptHandle']
        )
        print("Message processed and deleted.")



🐳 Step 2: Dockerfile

FROM python:3.10-slim

RUN pip install boto3

COPY consumer.py /app/consumer.py

WORKDIR /app

CMD ["python", "consumer.py"]


Build and push to a registry:

docker build -t <your-registry>/sqs-consumer:latest .
docker push <your-registry>/sqs-consumer:latest


🧩 Step 3: KEDA ScaledJob for SQS

apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-auth
spec:
  podIdentity:
    provider: aws-eks
---
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: sqs-scaledjob
spec:
  jobTargetRef:
    template:
      spec:
        containers:
        - name: sqs-consumer
          image: <your-registry>/sqs-consumer:latest
          env:
          - name: SQS_URL
            value: "https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>"
          - name: AWS_REGION
            value: "<region>"
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
        restartPolicy: Never
  pollingInterval: 30
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 2
  maxReplicaCount: 5
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: "https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>"
      queueLength: "1"
      awsRegion: "<region>"
      identityOwner: operator
    authenticationRef:
      name: aws-auth


📊 Step 4: Optional CloudWatch Logs Integration

If your EKS worker nodes already send stdout/stderr to CloudWatch, you’ll automatically see logs under /aws/eks/....

If not, you can:

    Add the Fluent Bit DaemonSet

    Or send logs manually using the AWS SDK

Best Practice: Use the built-in EKS logging by enabling:



aws eks update-cluster-config \
  --region <region> \
  --name <cluster-name> \
  --logging '{"clusterLogging":[{"types":["controllerManager","scheduler","api","authenticator"],"enabled":true}]}'


But for pod logs, CloudWatch requires a sidecar agent or Fluent Bit.

✅ Summary

| Component          | Purpose                                |
| ------------------ | -------------------------------------- |
| Python App         | Connects to SQS and processes messages |
| Docker Image       | Containerizes the app                  |
| KEDA ScaledJob     | Spins up worker pods per message       |
| IRSA (AWS EKS IAM) | Authenticates KEDA to pull metrics     |
| CloudWatch Logs    | Captures logs from pods                |


Would you like me to generate a GitHub-ready repo structure (Dockerfile, deployment.yaml, README.md) or a Helm chart for deploying all of this easily?



To generate a GitHub-ready repo with all necessary files, you'll need to log in to ChatGPT to use ChatGPT Canvas, where we can collaborate on the code structure.

In the meantime, here's a quick preview of the folder structure and key files I'll include:

📁 GitHub Repo Structure: keda-sqs-consumer


keda-sqs-consumer/
├── Dockerfile
├── consumer.py
├── k8s/
│   ├── scaledjob.yaml
│   ├── triggerauth.yaml
├── README.md
├── .gitignore


✅ Dockerfile

FROM python:3.10-slim

RUN pip install boto3

COPY consumer.py /app/consumer.py
WORKDIR /app

CMD ["python", "consumer.py"]


✅ consumer.py

(A Python SQS message consumer script – same as before.)


✅ k8s/scaledjob.yaml

apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: sqs-scaledjob
spec:
  jobTargetRef:
    template:
      spec:
        containers:
        - name: sqs-consumer
          image: <your-registry>/sqs-consumer:latest
          env:
          - name: SQS_URL
            value: "https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>"
          - name: AWS_REGION
            value: "<region>"
        restartPolicy: Never
  pollingInterval: 30
  maxReplicaCount: 5
  triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: aws-auth
    metadata:
      queueURL: "https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>"
      queueLength: "1"
      awsRegion: "<region>"
      identityOwner: operator


✅ k8s/triggerauth.yaml

apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-auth
spec:
  podIdentity:
    provider: aws-eks


✅ README.md Outline

    📦 Description

    🛠️ Prerequisites (EKS, IRSA, SQS)

    🐳 Docker Build Instructions

    🚀 Deployment Steps

    📡 Testing via aws sqs send-message

    🔍 Monitoring & Logs

Would you like me to zip this and give you a downloadable link or generate a GitHub template repo you can fork?



To download a ready-to-use zip, you'll need to log in to ChatGPT to enable Python support.

However, here’s the code you can run on your own machine to generate the GitHub-style project folder and zip it:
🔧 Python Script to Generate the Project

Save and run this on your local machine:

import zipfile
import os

base_dir = "keda-sqs-consumer"
os.makedirs(f"{base_dir}/k8s", exist_ok=True)

files = {
    f"{base_dir}/Dockerfile": """FROM python:3.10-slim

RUN pip install boto3

COPY consumer.py /app/consumer.py
WORKDIR /app

CMD ["python", "consumer.py"]
""",
    f"{base_dir}/consumer.py": """import boto3
import time
import os

sqs_url = os.getenv("SQS_URL")
region = os.getenv("AWS_REGION", "us-west-2")

sqs = boto3.client("sqs", region_name=region)

print(f"Listening for messages on: {sqs_url}")

def process_message(message):
    print(f"Received message: {message['Body']}")
    time.sleep(5)

while True:
    resp = sqs.receive_message(
        QueueUrl=sqs_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=10
    )

    messages = resp.get("Messages", [])
    if not messages:
        print("No messages, exiting.")
        break

    for msg in messages:
        process_message(msg)
        sqs.delete_message(
            QueueUrl=sqs_url,
            ReceiptHandle=msg['ReceiptHandle']
        )
        print("Message processed and deleted.")
""",
    f"{base_dir}/k8s/scaledjob.yaml": """apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: sqs-scaledjob
spec:
  jobTargetRef:
    template:
      spec:
        containers:
        - name: sqs-consumer
          image: <your-registry>/sqs-consumer:latest
          env:
          - name: SQS_URL
            value: "https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>"
          - name: AWS_REGION
            value: "<region>"
        restartPolicy: Never
  pollingInterval: 30
  maxReplicaCount: 5
  triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: aws-auth
    metadata:
      queueURL: "https://sqs.<region>.amazonaws.com/<account-id>/<queue-name>"
      queueLength: "1"
      awsRegion: "<region>"
      identityOwner: operator
""",
    f"{base_dir}/k8s/triggerauth.yaml": """apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-auth
spec:
  podIdentity:
    provider: aws-eks
""",
    f"{base_dir}/README.md": """# KEDA SQS Consumer

This project provides a scalable SQS consumer on EKS using KEDA's ScaledJob feature.

## 🧩 Components
- **Python consumer** for AWS SQS
- **KEDA ScaledJob** for per-message scaling
- **IRSA-authenticated trigger**

## 🚀 Usage

1. Build and push Docker image:

```bash
docker build -t <your-registry>/sqs-consumer:latest .
docker push <your-registry>/sqs-consumer:latest

Update k8s/scaledjob.yaml with your SQS URL and region.

Apply Kubernetes manifests:

kubectl apply -f k8s/triggerauth.yaml
kubectl apply -f k8s/scaledjob.yaml

Send a test message:

aws sqs send-message --queue-url <queue-url> --message-body "test message"

Watch pods spin up and logs:

kubectl get pods
kubectl logs <pod-name>


"""
}

for path, content in files.items():
with open(path, "w") as f:
f.write(content)

with zipfile.ZipFile("keda-sqs-consumer.zip", "w") as zipf:
for foldername, _, filenames in os.walk(base_dir):
for filename in filenames:
filepath = os.path.join(foldername, filename)
zipf.write(filepath)


---

This script creates a zip archive called `keda-sqs-consumer.zip` with everything you need. Let me know if you’d like help deploying it! ​:contentReference[oaicite:0]{index=0}​


