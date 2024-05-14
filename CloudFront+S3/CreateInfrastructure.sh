#!/bin/sh

die() {
    echo $*
    exit 1
}
# Settings
export AWS="aws --no-cli-pager --profile default"
export BUCKET_NAME="tx-test-static-contents"

# Create bucket
${AWS} s3api create-bucket --bucket ${BUCKET_NAME}

# Create OAC
cat <<EOF > OAC.cli
{
    "OriginAccessControlConfig": {
        "Name": "${BUCKET_NAME}.s3.us-east-1.amazonaws.com",
        "Description": "OAC for static content test",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }
}
EOF
${AWS} cloudfront create-origin-access-control --cli-input-json file://OAC.cli > OAC.result || die "Could not create OAC"
export OAC_ID=`egrep '[ \t]*"Id":' OAC.result | cut -f2 -d: | tr -d '", '`
echo "OAC_ID=${OAC_ID}"
export CALLER_REFERENCE=`date +%Y%m%d%H%M%S`
# Create distribution
cat <<EOF > DIST.cli  
{
    "DistributionConfig": {
        "CallerReference": "${CALLER_REFERENCE}",
        "Comment": "Ditribution to test serving static contents",
        "DefaultRootObject": "index.html",
        "Origins": {
            "Quantity": 1,
            "Items": [
                    {
                        "Id": "${BUCKET_NAME}.s3.us-east-1.amazonaws.com",
                        "DomainName": "${BUCKET_NAME}.s3.us-east-1.amazonaws.com",
                        "OriginPath": "",
                        "CustomHeaders": {
                            "Quantity": 0
                        },
                        "S3OriginConfig": {
                            "OriginAccessIdentity": ""
                        },
                        "ConnectionAttempts": 3,
                        "ConnectionTimeout": 10,
                        "OriginShield": {
                            "Enabled": false
                        },
                        "OriginAccessControlId": "${OAC_ID}"
                    }
            ]
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "${BUCKET_NAME}.s3.us-east-1.amazonaws.com",
            "ForwardedValues": {
                "QueryString": false,
                "Cookies": {
                    "Forward": "none"
                },
                "Headers": {
                    "Quantity": 0
                },
                "QueryStringCacheKeys": {
                    "Quantity": 0
                }
            },
            "MinTTL": 0,
            "ViewerProtocolPolicy": "https-only",
            "AllowedMethods": {
                "Quantity": 2,
                "Items": [
                    "HEAD",
                    "GET"
                ],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": [
                        "HEAD",
                        "GET"
                    ]
                }
            },
            "SmoothStreaming": false
        },
        "PriceClass": "PriceClass_100",
        "Enabled": true,
        "ViewerCertificate": {
            "CloudFrontDefaultCertificate": true,
            "SSLSupportMethod": "vip",
            "MinimumProtocolVersion": "TLSv1",
            "CertificateSource": "cloudfront"
        },
        "Restrictions": {
            "GeoRestriction": {
                "RestrictionType": "none",
                "Quantity": 0
            }
        },
        "HttpVersion": "http2",
        "IsIPV6Enabled": false,
        "Staging": false
    }
}
EOF
${AWS} cloudfront create-distribution --cli-input-json file://DIST.cli > DIST.result || die "Could not create distribution"
export DIST_ID=`egrep '[ \t]*"Id":' DIST.result | head -1 | cut -f2 -d: | tr -d '", '`
export DIST_ARN=`egrep '[ \t]*"ARN":' DIST.result | cut -f2- -d: | tr -d '", '`
export DIST_DOMAIN=`egrep '[ \t]*"DomainName":' DIST.result | grep cloudfront.net | cut -f2- -d: | tr -d '", '`
# Add bucket policy to allow CloudFront access
cat <<EOF > BUCKET_POLICY.cli
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "${DIST_ARN}"
                }
            }
        }
    ]
}
EOF
${AWS} s3api put-bucket-policy --bucket ${BUCKET_NAME} --policy file://BUCKET_POLICY.cli || die "Could not add bucket policy"
# Add test objects to the bucket
${AWS} s3 cp index.html s3://${BUCKET_NAME}/ || die "Could not add test object"
${AWS} s3 cp FantomLiberty.png s3://${BUCKET_NAME}/ || die "Could not add test object"
#
echo You can check the status of the distribution with: ${AWS} cloudfront get-distribution --id ${DIST_ID} and look for the status "Deployed"
echo You can access the distribution with: https://${DIST_DOMAIN}.cloudfront.net/

