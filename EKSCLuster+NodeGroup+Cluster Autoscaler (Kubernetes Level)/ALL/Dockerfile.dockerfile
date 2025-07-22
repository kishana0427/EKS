FROM hashicorp/terraform:1.7.5

# Install AWS CLI v2
RUN apk add --no-cache curl unzip python3 py3-pip && \
    pip3 install awscli && \
    aws --version

WORKDIR /workspace