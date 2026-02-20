# AWS Load Balancer Controller on EKS — Setup Guide

This guide walks you through installing the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) on an Amazon EKS cluster using IAM Roles for Service Accounts (IRSA).

---

## Prerequisites

- An EKS cluster with OIDC provider enabled (or the ability to add it).
- `kubectl` configured for your cluster.
- `aws` CLI configured with credentials that can create IAM policies, roles, and modify the cluster.
- `helm` 3.x installed.

**Values you will need:** replace these placeholders throughout the steps with your own:

| Placeholder      | Description |
|------------------|-------------|
| `<cluster-name>` | Your EKS cluster name |
| `<region>`       | AWS region (e.g. `us-east-1`) |
| `<vpc-id>`       | VPC ID where the EKS cluster runs |
| `<ACCOUNT_ID>`   | Your AWS account ID (12 digits) |

---

## Step 1: Get the cluster OIDC issuer

Retrieve your cluster’s OIDC issuer URL (used later for the IAM trust policy and, if needed, to create the OIDC provider):

```bash
aws eks describe-cluster \
  --name <cluster-name> \
  --query "cluster.identity.oidc.issuer" \
  --output text
```

Example output: `https://oidc.eks.us-east-1.amazonaws.com/id/C877FBF6772ACD393D391360C2468BD7`

If your cluster does not have an OIDC provider associated in IAM, create it using the [EKS documentation](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html).

---

## Step 2: Create the IAM policy

Save the following as `iam_policy.json` in your working directory:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "ec2:GetSecurityGroupsForVpc",
                "ec2:DescribeIpamPools",
                "ec2:DescribeRouteTables",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTrustStores",
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:DescribeCapacityReservation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:ModifyListenerAttributes",
                "elasticloadbalancing:ModifyCapacityReservation",
                "elasticloadbalancing:ModifyIpPools"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "StringEquals": {
                    "elasticloadbalancing:CreateAction": [
                        "CreateTargetGroup",
                        "CreateLoadBalancer"
                    ]
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule",
                "elasticloadbalancing:SetRulePriorities"
            ],
            "Resource": "*"
        }
    ]
}
```

Create the policy in AWS:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

Note the policy ARN in the output (e.g. `arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy`). You will use it when attaching the policy to the role.

---

## Step 3: Create the IAM role and trust policy (IRSA)

Create a role that the controller’s Kubernetes service account will assume via IRSA.

1. **Build the OIDC provider ARN**  
   From Step 1 you have an issuer like:  
   `https://oidc.eks.us-east-1.amazonaws.com/id/C877FBF6772ACD393D391360C2468BD7`  
   The IAM OIDC provider ARN format is:  
   `arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<OIDC_ID>`  
   Example: `arn:aws:iam::426043895157:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/C877FBF6772ACD393D391360C2468BD7`

2. **Save the trust policy** as `trust-policy.json`. Replace:
   - `<OIDC_PROVIDER_ARN>` — e.g. `arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<OIDC_ID>`
   - `<OIDC_ISSUER>:sub` — the condition key must be your issuer URL with `https://` removed, plus `:sub`. Example: `oidc.eks.us-east-1.amazonaws.com/id/C877FBF6772ACD393D391360C2468BD7:sub`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "<OIDC_PROVIDER_ARN>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "<OIDC_ISSUER>:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
```

Example with real values: if the issuer is `https://oidc.eks.us-east-1.amazonaws.com/id/C877FBF6772ACD393D391360C2468BD7`, then the condition key is `oidc.eks.us-east-1.amazonaws.com/id/C877FBF6772ACD393D391360C2468BD7:sub`.

3. **Create the role** (use a role name that matches your naming convention, e.g. `<cluster-name>-aws-lb-controller`):

```bash
aws iam create-role \
  --role-name <cluster-name>-aws-lb-controller \
  --assume-role-policy-document file://trust-policy.json
```

4. **Attach the IAM policy** to the role:

```bash
aws iam attach-role-policy \
  --role-name <cluster-name>-aws-lb-controller \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy
```

---

## Step 4: Create the Kubernetes service account

Create a ServiceAccount in `kube-system` with the IAM role ARN so the controller pod can assume the role:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/<cluster-name>-aws-lb-controller
```

Apply it (after replacing `<ACCOUNT_ID>` and `<cluster-name>`):

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/<cluster-name>-aws-lb-controller
EOF
```

---

## Step 5: Install the controller with Helm

Add the EKS Helm repo and install the AWS Load Balancer Controller. Use the same cluster name, region, and VPC ID as your EKS cluster, and point Helm at the existing service account:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set region=<region> \
  --set vpcId=<vpc-id> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## Verification

Check that the controller is running:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

To expose a service with an ALB, use an `Ingress` with the appropriate annotations (e.g. `kubernetes.io/ingress.class: alb`) or a `Service` of type `LoadBalancer` as per the [AWS Load Balancer Controller documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/).

---

## Summary

| Step | What you did |
|------|-------------------------------|
| 1    | Retrieved cluster OIDC issuer |
| 2    | Created IAM policy `AWSLoadBalancerControllerIAMPolicy` |
| 3    | Created IAM role with OIDC trust policy and attached the policy |
| 4    | Created Kubernetes ServiceAccount with `eks.amazonaws.com/role-arn` |
| 5    | Installed controller via Helm into `kube-system` |

If you use a different cluster name, region, or account, ensure the role name, trust policy, and ServiceAccount annotation stay consistent with the same IAM role ARN.

---

## Kustomize Components (ingress-nginx and ALB)

You can install an ingress controller via Kustomize components so it is managed in the same overlay as the rest of the app. Two components are provided; **pick one** per overlay.

### Enabling Helm in Kustomize

Components that ship the controller use Helm charts. Build with Helm enabled:

```bash
kustomize build --enable-helm overlays/<your-overlay> | kubectl apply -f -
```

Or with kubectl:

```bash
kubectl kustomize overlays/<your-overlay> --enable-helm | kubectl apply -f -
```

### Option 1: ingress-nginx component

1. In your overlay `kustomization.yaml`, add the component under `components:`:
   ```yaml
   components:
     - ../../components/ingress-nginx
   ```
2. In `vars.yaml` (or `overlay-vars` ConfigMap), set:
   ```yaml
   INGRESS_CLASS: "nginx"
   ```
3. Optionally edit `kustomize/components/ingress-nginx/values.yaml` (e.g. `controller.service.type`, replicas, tolerations).
4. Build and apply with `--enable-helm` as above.

The component installs the ingress-nginx Helm chart and patches the base Ingress with nginx-specific annotations (e.g. `proxy-body-size`).

### Option 2: AWS Load Balancer Controller component

1. Complete **Steps 1–4** in this document (OIDC, IAM policy, IAM role + attach policy, and the IRSA ServiceAccount). The component expects that ServiceAccount to exist in `kube-system`; you can create it manually or let the component provide it (see below).
2. In your overlay `kustomization.yaml`, add the component under `components:`:
   ```yaml
   components:
     - ../../components/aws-load-balancer-controller
   ```
3. In `vars.yaml`, set:
   ```yaml
   INGRESS_CLASS: "alb"
   ```
4. Edit the component’s `values.yaml` and, if you use the component’s ServiceAccount, its `service-account.yaml`:
   - **values.yaml:** set `clusterName`, `region`, and `vpcId` to your EKS cluster values.
   - **service-account.yaml:** set `<ACCOUNT_ID>` and `<cluster-name>` in the `eks.amazonaws.com/role-arn` annotation to match the IAM role you created in Step 3.
5. Build and apply with `--enable-helm` as above.

The component installs the AWS Load Balancer Controller Helm chart (and optionally the IRSA ServiceAccount), and patches the base Ingress with ALB annotations (`scheme`, `target-type`, `listen-ports`).

### Summary

| Choice | Component | `vars.yaml` INGRESS_CLASS | Customize |
|--------|-----------|---------------------------|-----------|
| NGINX Ingress | `../../components/ingress-nginx` | `nginx` | `components/ingress-nginx/values.yaml` |
| AWS ALB | `../../components/aws-load-balancer-controller` | `alb` | `components/aws-load-balancer-controller/values.yaml` and `service-account.yaml` |

Use only one of these components per overlay so the same Ingress is not patched by both controllers.
