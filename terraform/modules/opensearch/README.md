## OpenSearch module (Bedrock integration)

### Bedrock connector integration (optional)

This module can optionally deploy the OpenSearch ↔ Bedrock integration **via a CloudFormation stack** (it uses the vendored template `bedrock-connector.cloudformation.yml`).

- **Enable/disable**: set `create_connector = true` to create the connector + model registration resources; otherwise the module only provisions the OpenSearch domain.
- **Network requirement**: the Bedrock connector stack must run in the **same VPC/subnets/security group** as the OpenSearch domain. This module enforces that by:
  - VPC-enabling the domain when `enable_vpc = true`
  - Creating a dedicated OpenSearch SG and reusing it for the connector Lambda by default

### Required manual prerequisite (OpenSearch Security role mapping)

The CloudFormation template creates/uses the IAM role named by `lambda_invoke_opensearch_mlcommons_role_name` (default `LambdaInvokeOpenSearchMLCommonsRole`) for the connector Lambda to call OpenSearch.

Before (or immediately after) deploying the connector stack, you must map this IAM role to OpenSearch’s built-in **`ml_full_access`** role in the OpenSearch Security plugin.

- **Where**: OpenSearch Dashboards → *Security* → *Roles* → `ml_full_access` → *Mapped users / backend roles*
- **What to map**: the IAM role ARN `arn:aws:iam::<account_id>:role/<lambda_invoke_opensearch_mlcommons_role_name>`

If this mapping is missing, the connector/model registration step will fail even though the IAM role exists in AWS.

#### How we applied the role mapping (via curl)

Verify the OpenSearch cluster is reachable:

```bash
curl -u 'admin:<admin-password>' https://<opensearch-endpoint>
```

Map `LambdaInvokeOpenSearchMLCommonsRole` to `ml_full_access`:

```bash
curl -X PUT \
  'https://<opensearch-endpoint>/_plugins/_security/api/rolesmapping/ml_full_access' \
  -H 'Content-Type: application/json' \
  -u 'admin:<admin-password>' \
  -d '{
    "backend_roles": [
      "arn:aws:iam::<account-id>:role/LambdaInvokeOpenSearchMLCommonsRole"
    ]
  }'
# {"status":"CREATED","message":"'ml_full_access' created."}
```

Also map to `all_access` (required for the Lambda to register the model):

```bash
curl -X PUT \
  'https://<opensearch-endpoint>/_plugins/_security/api/rolesmapping/all_access' \
  -H 'Content-Type: application/json' \
  -u 'admin:<admin-password>' \
  -d '{
    "backend_roles": [
      "arn:aws:iam::<account-id>:role/LambdaInvokeOpenSearchMLCommonsRole"
    ]
  }'
# {"status":"OK","message":"'all_access' updated."}
```

