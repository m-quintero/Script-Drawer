##################################################################################################################################################
# Script Name: orgmailsearch.sh
# Author: michael.quintero@rackspace.com
# Description: This script will search either commerical or government master payer accounts for email addresses associated with a given account #
# Pre-requisties: You will need to have the aws cli and jq installed, as well as the temp credentials from Janus
##################################################################################################################################################

#!/bin/bash

show_help() {
    echo "Usage: $0 -a ACCOUNT_NUMBER -t TYPE -h"
    echo ""
    echo "Options:"
    echo "  -a    Specify the AWS account number to search for."
    echo "  -t    Specify the account type: 'com' for Commercial or 'gov' for Government."
    echo "        This determines the output file name ('commercial.txt' or 'government.txt')."
    echo "  -h    Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $0 -a 123456789012 -t com"
    echo "  This will search for the account number '123456789012' in commercial accounts and output to 'commercial.txt'."
}

if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq to use this script."
    exit 1
fi

if ! command -v aws &> /dev/null
then
    echo "AWS CLI could not be found. Please install AWS CLI to use this script."
    exit 1
fi

ACCOUNT_NUMBER=""
ACCOUNT_TYPE=""
HELP_REQUESTED=0

while getopts "ha:t:" opt; do
  case $opt in
    h) HELP_REQUESTED=1 ;;
    a) ACCOUNT_NUMBER=$OPTARG ;;
    t) ACCOUNT_TYPE=$OPTARG ;;
    \?) show_help
        exit 1
        ;;
  esac
done

if [ "$HELP_REQUESTED" -eq 1 ]; then
    show_help
    exit 0
fi

if [ -z "$ACCOUNT_NUMBER" ]; then
    echo "Account number (-a) is required."
    exit 1
fi

if [ -z "$ACCOUNT_TYPE" ]; then
    echo "Account type (-t) is required."
    exit 1
fi

if [ "$ACCOUNT_TYPE" != "com" ] && [ "$ACCOUNT_TYPE" != "gov" ]; then
    echo "Account type (-t) must be either 'com' for Commercial or 'gov' for Government."
    exit 1
fi

FILE_NAME=""
if [ "$ACCOUNT_TYPE" == "com" ]; then
    FILE_NAME="commercial.txt"
elif [ "$ACCOUNT_TYPE" == "gov" ]; then
    FILE_NAME="government.txt"
fi

aws organizations list-accounts --output json > "$FILE_NAME"

EMAIL=$(jq -r --arg ACCOUNT_NUMBER "$ACCOUNT_NUMBER" '.Accounts[] | select(.Id==$ACCOUNT_NUMBER) | .Email' "$FILE_NAME")

if [ -z "$EMAIL" ]; then
    echo "No email found for account number $ACCOUNT_NUMBER."
else
    echo "Email for account $ACCOUNT_NUMBER is $EMAIL"
fi

# Optional: Clean up your mess!
# rm "$FILE_NAME"
