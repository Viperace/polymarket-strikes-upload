#!/usr/bin/env bash
# One-time AWS setup for polymarket-strikes-upload. Run in AWS CloudShell:
#   bash setup_cloudshell.sh <bucket-name> [prefix]
# Creates (or updates) the CloudFormation stack "polymarket-strikes-github":
# an IAM role that GitHub Actions in Viperace/polymarket-strikes-upload (main
# branch only) can assume to read/write s3://<bucket>/<prefix>/*. No access keys.
set -euo pipefail

BUCKET="${1:?usage: bash setup_cloudshell.sh <bucket-name> [prefix]}"
PREFIX="${2:-polymarket_reference}"
PREFIX="${PREFIX#/}"; PREFIX="${PREFIX%/}"
STACK=polymarket-strikes-github

aws s3api head-bucket --bucket "$BUCKET" >/dev/null || { echo "Bucket $BUCKET not reachable from this account"; exit 1; }
REGION=$(aws s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text)
[ "$REGION" = "None" ] || [ -z "$REGION" ] && REGION=us-east-1

if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text \
     | tr '\t' '\n' | grep -q 'oidc-provider/token.actions.githubusercontent.com$'; then
  CREATE_PROVIDER=false
else
  CREATE_PROVIDER=true
fi

TEMPLATE=$(mktemp --suffix=.yaml)
cat > "$TEMPLATE" <<'YAML'
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  Lets GitHub Actions in one repository read and write the strike CSVs under
  one S3 prefix, using short-lived OIDC credentials (no stored access keys).

Parameters:
  BucketName:
    Type: String
    Description: Existing S3 bucket that will hold the strike CSVs.
  Prefix:
    Type: String
    Default: polymarket_reference
    Description: Folder (key prefix) inside the bucket, without slashes at either end.
  GitHubRepo:
    Type: String
    Default: Viperace/polymarket-strikes-upload
    Description: owner/repo allowed to assume the role.
  Branch:
    Type: String
    Default: main
    Description: Only workflow runs on this branch may assume the role.
  CreateOIDCProvider:
    Type: String
    AllowedValues: ["true", "false"]
    Default: "true"
    Description: >
      Set to false if this AWS account already has the
      token.actions.githubusercontent.com identity provider (IAM > Identity providers).

Conditions:
  MakeProvider: !Equals [!Ref CreateOIDCProvider, "true"]

Resources:
  GitHubOIDCProvider:
    Type: AWS::IAM::OIDCProvider
    Condition: MakeProvider
    Properties:
      Url: https://token.actions.githubusercontent.com
      ClientIdList:
        - sts.amazonaws.com
      ThumbprintList:
        - 6938fd4d98bab03faadb97b34396831e3780aea1
        - 1c58a3a8518e8759bf075b76b750d4f2df264fcd

  StrikesRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: github-polymarket-strikes
      MaxSessionDuration: 3600
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Federated: !If
                - MakeProvider
                - !Ref GitHubOIDCProvider
                - !Sub arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                token.actions.githubusercontent.com:aud: sts.amazonaws.com
                token.actions.githubusercontent.com:sub: !Sub repo:${GitHubRepo}:ref:refs/heads/${Branch}
      Policies:
        - PolicyName: strike-csvs
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Sid: ReadWriteStrikeFiles
                Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                Resource: !Sub arn:aws:s3:::${BucketName}/${Prefix}/*
              - Sid: ListStrikePrefix
                Effect: Allow
                Action: s3:ListBucket
                Resource: !Sub arn:aws:s3:::${BucketName}
                Condition:
                  StringLike:
                    s3:prefix:
                      - !Sub ${Prefix}/*

Outputs:
  RoleArn:
    Description: Paste this into the repo variable AWS_ROLE_ARN.
    Value: !GetAtt StrikesRole.Arn
YAML

aws cloudformation deploy \
  --stack-name "$STACK" \
  --template-file "$TEMPLATE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides BucketName="$BUCKET" Prefix="$PREFIX" CreateOIDCProvider="$CREATE_PROVIDER"

ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" --output text)

echo
echo "Done. Send these four lines back:"
echo "AWS_ROLE_ARN=$ROLE_ARN"
echo "AWS_REGION=$REGION"
echo "S3_BUCKET=$BUCKET"
echo "S3_PREFIX=$PREFIX"
