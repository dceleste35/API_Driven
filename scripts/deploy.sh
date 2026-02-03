#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Defaults (safe for LocalStack)
# -----------------------------
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# In Codespaces: set AWS_ENDPOINT to the PUBLIC URL of port 4566
# Locally: default works
export AWS_ENDPOINT="${AWS_ENDPOINT:-http://localhost:4566}"

AWS="aws --endpoint-url=${AWS_ENDPOINT} --region ${AWS_DEFAULT_REGION}"

echo "==> Using:"
echo "    AWS_ENDPOINT=${AWS_ENDPOINT}"
echo "    AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
echo

# -----------------------------
# Pre-flight checks
# -----------------------------
command -v aws >/dev/null 2>&1 || {
  echo "ERROR: aws CLI not found."
  echo "Install AWS CLI v2 before running deploy."
  exit 1
}

command -v zip >/dev/null 2>&1 || {
  echo "==> Installing zip"
  sudo apt-get update -y && sudo apt-get install -y zip >/dev/null
}

# -----------------------------
# 1) IAM Role for Lambda (LocalStack)
# -----------------------------
ROLE_NAME="lambda-ec2-role"
TRUST_POLICY='{
  "Version":"2012-10-17",
  "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
}'

echo "==> Creating/ensuring IAM role: ${ROLE_NAME}"
set +e
$AWS iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1
ROLE_EXISTS=$?
set -e

if [ $ROLE_EXISTS -ne 0 ]; then
  $AWS iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" >/dev/null
fi

ROLE_ARN="$($AWS iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)"

# Attach a permissive policy (LocalStack TP simplicity)
# For a TP it's ok; in real AWS you'd use least privilege.
POLICY_DOC='{
  "Version":"2012-10-17",
  "Statement":[
    {"Effect":"Allow","Action":["ec2:StartInstances","ec2:StopInstances","ec2:DescribeInstances"],"Resource":"*"},
    {"Effect":"Allow","Action":["logs:*"],"Resource":"*"}
  ]
}'

echo "==> Putting inline policy"
$AWS iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "lambda-ec2-policy" \
  --policy-document "${POLICY_DOC}" >/dev/null

# -----------------------------
# 2) Package Lambda
# -----------------------------
FUNCTION_NAME="ec2-control"
HANDLER_FILE="lambda/handler.py"

if [ ! -f "${HANDLER_FILE}" ]; then
  echo "ERROR: Missing ${HANDLER_FILE}"
  echo "Create lambda/handler.py (see README section) then re-run."
  exit 1
fi

echo "==> Packaging Lambda"
rm -f /tmp/lambda.zip
(
  cd lambda
  zip -qr /tmp/lambda.zip handler.py
)

# -----------------------------
# 3) Create/Update Lambda function
# -----------------------------
echo "==> Creating/updating Lambda: ${FUNCTION_NAME}"
set +e
$AWS lambda get-function --function-name "${FUNCTION_NAME}" >/dev/null 2>&1
FN_EXISTS=$?
set -e

if [ $FN_EXISTS -ne 0 ]; then
  $AWS lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --runtime python3.11 \
    --handler handler.lambda_handler \
    --role "${ROLE_ARN}" \
    --zip-file "fileb:///tmp/lambda.zip" \
    --environment "Variables={AWS_ENDPOINT=${AWS_ENDPOINT},AWS_REGION=${AWS_DEFAULT_REGION}}" \
    >/dev/null
else
  $AWS lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb:///tmp/lambda.zip" \
    >/dev/null

  $AWS lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --environment "Variables={AWS_ENDPOINT=${AWS_ENDPOINT},AWS_REGION=${AWS_DEFAULT_REGION}}" \
    >/dev/null
fi

LAMBDA_ARN="$($AWS lambda get-function --function-name "${FUNCTION_NAME}" --query 'Configuration.FunctionArn' --output text)"

# -----------------------------
# 4) API Gateway REST API + route POST /ec2
# -----------------------------
API_NAME="api-driven-ec2"
STAGE="dev"

echo "==> Creating/ensuring API Gateway: ${API_NAME}"
REST_API_ID="$($AWS apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id | [0]" --output text)"
if [ "${REST_API_ID}" = "None" ] || [ -z "${REST_API_ID}" ]; then
  REST_API_ID="$($AWS apigateway create-rest-api --name "${API_NAME}" --query 'id' --output text)"
fi

ROOT_ID="$($AWS apigateway get-resources --rest-api-id "${REST_API_ID}" --query 'items[?path==`/`].id | [0]' --output text)"

# Create /ec2 resource
EC2_RES_ID="$($AWS apigateway get-resources --rest-api-id "${REST_API_ID}" --query "items[?path=='/ec2'].id | [0]" --output text)"
if [ "${EC2_RES_ID}" = "None" ] || [ -z "${EC2_RES_ID}" ]; then
  EC2_RES_ID="$($AWS apigateway create-resource --rest-api-id "${REST_API_ID}" --parent-id "${ROOT_ID}" --path-part "ec2" --query 'id' --output text)"
fi

# Put method POST
echo "==> Configuring POST /ec2"
set +e
$AWS apigateway get-method --rest-api-id "${REST_API_ID}" --resource-id "${EC2_RES_ID}" --http-method POST >/dev/null 2>&1
METHOD_EXISTS=$?
set -e
if [ $METHOD_EXISTS -ne 0 ]; then
  $AWS apigateway put-method \
    --rest-api-id "${REST_API_ID}" \
    --resource-id "${EC2_RES_ID}" \
    --http-method POST \
    --authorization-type "NONE" >/dev/null
fi

# Integration (Lambda proxy)
URI="arn:aws:apigateway:${AWS_DEFAULT_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

$AWS apigateway put-integration \
  --rest-api-id "${REST_API_ID}" \
  --resource-id "${EC2_RES_ID}" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "${URI}" >/dev/null

# -----------------------------
# 5) Allow API Gateway to invoke Lambda
# -----------------------------
echo "==> Adding Lambda permission for API Gateway"
# Statement id must be unique; ignore if already exists
set +e
$AWS lambda add-permission \
  --function-name "${FUNCTION_NAME}" \
  --statement-id "apigw-invoke" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${AWS_DEFAULT_REGION}:000000000000:${REST_API_ID}/*/POST/ec2" \
  >/dev/null 2>&1
set -e

# -----------------------------
# 6) Deploy API
# -----------------------------
echo "==> Deploying API to stage: ${STAGE}"
$AWS apigateway create-deployment --rest-api-id "${REST_API_ID}" --stage-name "${STAGE}" >/dev/null

# LocalStack user_request URL format:
API_URL="${AWS_ENDPOINT}/restapis/${REST_API_ID}/${STAGE}/_user_request_"

echo
echo "✅ DEPLOY OK"
echo "REST_API_ID=${REST_API_ID}"
echo "API_URL=${API_URL}"
echo
echo "Test:"
echo "curl -s -X POST \"${API_URL}/ec2\" -H \"Content-Type: application/json\" -d '{\"action\":\"stop\",\"instanceId\":\"i-...\"}' | cat"
