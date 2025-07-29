kubectl run load-generator \
  --image=williamyeh/hey:latest \
  --restart=Never -- -c 1 -q 5 -z 60m http://my-deploy.default.svc.cluster.local
