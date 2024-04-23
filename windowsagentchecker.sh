# Script Name: agentchecker.sh
# Author: michael.quintero@rackspace.com
# Description: This script will verify the status of services for the TIERS project
# Pre-Requisites: AWS Cli as well as the account credentials either set via 'aws configure' or copypasta'd from Janus
# Usage: agentchecker.sh -o $WINDOWS_OR_LINUX -r $ENTER_REGION -f /path/to/file/with/instance_ids
# Example: bash agentchecker.sh -o linux -r us-east-1 -f instance_id.txt

#!/bin/bash

os_type=""
input_file=""
region="us-east-2" # Default region

while getopts "o:f:r:" opt; do
  case $opt in
    o) os_type="$OPTARG";;
    f) input_file="$OPTARG";;
    r) region="$OPTARG";;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1;;
  esac
done

if [ -z "$os_type" ] || [ -z "$input_file" ]; then
  echo "Usage: $0 -o <os_type> -f <input_file> [-r <region>]"
  exit 1
fi

mapfile -t instance_ids < <(grep 'i-' "$input_file")

for instance_id in "${instance_ids[@]}"; do
  echo "Processing instance ID: $instance_id"

  if [ "$os_type" == "linux" ]; then
    command_output=$(aws ssm send-command \
      --document-name "AWS-RunShellScript" \
      --instance-ids "$instance_id" \
      --parameters 'commands=[
        "hostname ; uname -r",
        "echo Checking aws-kinesis-agent service; systemctl is-active aws-kinesis-agent",
        "echo Checking amazon-cloudwatch-agent service; systemctl is-active amazon-cloudwatch-agent",
        "echo Checking amazon-ssm-agent service; systemctl is-active amazon-ssm-agent",
        "echo Checking qualys-cloud-agent service; systemctl is-active qualys-cloud-agent",
        "echo Checking falcon-sensor service; systemctl is-active falcon-sensor",
        "echo Checking enlinuxpc64 service; systemctl is-active enlinuxpc64",
        "echo Checking splunkd service; systemctl is-active splunkd",
	      "echo Checking Splunk logs; tail -10 /opt/rackspace/splunkforwarder/var/log/splunk/splunkd.log | grep idx",
        "echo Checking sftd service; systemctl is-active sftd"
      ]' \
      --output text \
      --query "Command.CommandId" \
      --region "$region")
  elif [ "$os_type" == "windows" ]; then
    command_output=$(aws ssm send-command \
      --document-name "AWS-RunPowerShellScript" \
      --instance-ids "$instance_id" \
      --parameters 'commands=["hostname; Get-Service besclient; Get-Service QualysAgent; Get-Service Amazon*; Get-Service AWS*; Get-Service Scale*; Get-Service enstartdir; Get-Service CSFalconService; Get-Service Splunk*; gc \"C:\\Program Files\\SplunkForwarderRAX\\var\\log\\splunk\\splunkd.log\" | Select-String \"idx\" | Select-Object -Last 1"]' \
      --output text \
      --query "Command.CommandId" \
      --region "$region")
  else
    echo "Unsupported OS type. Please use -o to specify 'linux' or 'windows'."
    exit 1
  fi

  echo "Command sent, Command ID: $command_output"

  echo "Waiting for 10 seconds..."
  sleep 10

  aws ssm list-command-invocations \
    --command-id "$command_output" \
    --details \
    --output text \
    --query "CommandInvocations[*].{InstanceId:InstanceId,Status:Status,Output:CommandPlugins[0].Output}" \
    --region "$region"
done
