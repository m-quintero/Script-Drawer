# https://docs.aws.amazon.com/cli/latest/reference/ssm/send-command.html
# For this script to work, you need to have a file where you have all your EC2 instance IDs in. I named it 'instance_id.txt' for this script. Adjust as needed. This script will process a batch, iterating through every instance with a 10 second sleep before checking the results of the requested action(s)
# BEWARE!!!! Also hard variable for the region, currently set to us-east-2. Again, adjust as needed.
# The syntax is bash check_agents_linux.sh. Be sure to grab the temporary credentials from Janus before running, or you'll have a bad day.

#!/bin/bash

input_file="instance_id.txt"

mapfile -t instance_ids < <(grep 'i-' "$input_file")

for instance_id in "${instance_ids[@]}"; do
  echo "Processing instance ID: $instance_id"

  command_output=$(aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "$instance_id" \
    --parameters 'commands=[
      "echo For; hostname",
      "echo Checking aws-kinesis-agent service; systemctl is-active aws-kinesis-agent",
      "echo Checking amazon-cloudwatch-agent service; systemctl is-active amazon-cloudwatch-agent",
      "echo Checking amazon-ssm-agent service; systemctl is-active amazon-ssm-agent",
      "echo Checking qualys-cloud-agent service; systemctl is-active qualys-cloud-agent",
      "echo Checking falcon-sensor service; systemctl is-active falcon-sensor",
      "echo Checking enlinuxpc64 service; systemctl is-active enlinuxpc64",
      "echo Checking splunkd service; systemctl is-active splunkd",
      "echo Checking sftd service; systemctl is-active sftd"
    ]' \
    --output text \
    --query "Command.CommandId" \
    --region us-east-2)

  echo "Command sent, Command ID: $command_output"

  echo "Waiting for 10 seconds..."
  sleep 10

  aws ssm list-command-invocations \
    --command-id "$command_output" \
    --details \
    --output text \
    --query "CommandInvocations[*].{InstanceId:InstanceId,Status:Status,Output:CommandPlugins[0].Output}" \
    --region us-east-2
done
