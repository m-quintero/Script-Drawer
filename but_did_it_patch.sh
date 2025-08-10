# NAME: but_did_it_patch.sh
# AUTHOR: michael.quintero@rackspace.com
# PURPOSE: Run a remote bash script to ensure that the machine patched and rebooted, using AWS SSM
# FEATURES: All you need is the region, instance ID, and the change number.
# REQUIREMENTS: Bash, AWS Cli, AWS Account Credentials
# COMMENT: but_did_it_patch.sh borrows from the Doubletake script as seen in https://github.com/m-quintero/Linux_Patcher, but is for a single action. If you are needing to run across multiple instances at a time, see the doubletake script.

#!/bin/bash

set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 -r REGION -i INSTANCE_ID -c CHANGE_ID

  -r, --region       AWS region (e.g. us-gov-west-1)
  -i, --instance     EC2 instance ID
  -c, --change       Change ID to assign to \$CHANGE in the remote script

Example:
  $0 -r us-gov-west-1 -i i-0123456789abcdef0 -c CHG0453578
USAGE
  exit 1
}

REGION=""; INSTANCE=""; CHANGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)   REGION="$2"; shift 2 ;;
    -i|--instance) INSTANCE="$2"; shift 2 ;;
    -c|--change)   CHANGE="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$REGION" || -z "$INSTANCE" || -z "$CHANGE" ]] && usage

# -------- Embedded check_kernel.sh content --------
REMOTE_SCRIPT=$(cat <<EOF
#!/bin/bash
CHANGE=$CHANGE
hostname
date
uptime
k_target=\$(grep -Eo 'kernel-[0-9]+\\.[0-9]+\\.[0-9]+-[^ ]+' /root/\$CHANGE/patchme.sh | sed 's/^kernel-//')
if [[ "\$(uname -r)" == "\$k_target"* ]]; then
  echo "Kernel matches: \$k_target"
else
  echo "Mismatch: running \$(uname -r), expected \$k_target"
fi
yum history | grep \$(date +%F)
EOF
)
# --------------------------------------------------

# Here, we'll turn the script into scrambled letters so it doesn’t get messed up when we send it to the other computer.
B64=$(echo "$REMOTE_SCRIPT" | base64 | tr -d '\n')

echo "Sending remote check script to instance $INSTANCE in $REGION..."

CID=$(aws ssm send-command --region "$REGION" --document-name "AWS-RunShellScript" --instance-ids "$INSTANCE" --comment "Remote kernel/yum validation with CHANGE=$CHANGE" --parameters "commands=[
    \"bash -c 'echo $B64 | base64 -d > /tmp/remote_script.sh; chmod +x /tmp/remote_script.sh; cat <<EOF > /tmp/ssm_wrapper.sh
#!/bin/bash
/tmp/remote_script.sh
RET=\\\$?
rm -f /tmp/remote_script.sh
exit \\\$RET
EOF
chmod +x /tmp/ssm_wrapper.sh && /tmp/ssm_wrapper.sh'\"
  ]" \
  --query "Command.CommandId" --output text)

echo "CommandId: $CID"
echo -n "Waiting for command to finish"; while :; do
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --instance-id "$INSTANCE" --command-id "$CID" --query 'Status' --output text 2>/dev/null || echo "Pending")
  case "$STATUS" in
    Success|Failed|TimedOut|Cancelled) echo " → $STATUS"; break ;;
    InProgress|Pending|Delayed) echo -n "."; sleep 2 ;;
    *) echo -n "."; sleep 2 ;;
  esac
done

echo
echo "=== STDOUT ==="
aws ssm get-command-invocation --region "$REGION" --instance-id "$INSTANCE" --command-id "$CID" --query 'StandardOutputContent' --output text

echo
echo "=== STDERR ==="
aws ssm get-command-invocation --region "$REGION" --instance-id "$INSTANCE" --command-id "$CID" --query 'StandardErrorContent' --output text
