import json
import os
import boto3

def lambda_handler(event, context):
    endpoint = os.environ.get("AWS_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))

    ec2 = boto3.client("ec2", endpoint_url=endpoint, region_name=region)

    # API Gateway proxy => body is a string
    body_raw = event.get("body") or "{}"
    if isinstance(body_raw, str):
        try:
            body = json.loads(body_raw)
        except Exception:
            body = {}
    else:
        body = body_raw

    action = (body.get("action") or "").lower()
    instance_id = body.get("instanceId")

    if action not in ("start", "stop"):
        return _resp(400, {"error": "Invalid action. Use 'start' or 'stop'."})

    if not instance_id:
        return _resp(400, {"error": "Missing instanceId in JSON body."})

    if action == "start":
        ec2.start_instances(InstanceIds=[instance_id])
    else:
        ec2.stop_instances(InstanceIds=[instance_id])

    state = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"][0]["Instances"][0]["State"]["Name"]

    return _resp(200, {"ok": True, "action": action, "instanceId": instance_id, "state": state})


def _resp(status, payload):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }
