# Security Findings and Remediation

## Scope

Reviewed the Terraform configuration for the Acme Health clinical document platform. The review focused on AWS identity and access management, S3 storage, database exposure, secrets handling, container security, audit logging, and CI/CD credentials.

No AWS deployment or production changes were performed as part of this review.

## Findings Summary

| ID | Finding | Risk | Remediation / Status |
|---|---|---|---|
| F-01 | Terraform state encryption disabled | Sensitive infrastructure data in state may lack encryption at rest. | Enabled S3 backend encryption. Verify state bucket encryption, access controls, versioning, and recovery settings. |
| F-02 | Raw landing bucket policy used wildcard principal | Sensitive clinical documents could be exposed through overly broad partner access. | Removed the wildcard-principal policy and enabled all S3 public-access-block settings. Reconfigure partner access using approved, prefix-scoped identities or presigned URLs before restoring uploads. |
| F-03 | Audit log bucket allowed force destruction | Audit evidence could be deleted accidentally during infrastructure changes. | Set `force_destroy = false`. Review retention and recovery requirements. |
| F-04 | CloudTrail had limited regional coverage and no log-file validation | Security events in other regions could be missed, and log integrity checks were disabled. | Enabled multi-region trail coverage and log-file validation. Review event selectors and log retention. |
| F-05 | ECR image tags were mutable and push scanning was disabled | Image versions could be overwritten and known vulnerabilities could go undetected. | Enabled immutable image tags and scan-on-push. Use a unique release tag, preferably the Git commit SHA, and establish a vulnerability remediation process. |
| F-06 | ECS task role had overly broad permissions | A compromised task could perform unauthorized AWS actions or access unrelated resources. | Restricted S3 listing and reads to the incoming document prefix. Add other permissions only when justified by documented application needs. |
| F-07 | Database password was configured through Terraform and exposed in the task environment | Credentials could be exposed through configuration, state, or deployment metadata. | Enabled RDS-managed master credentials in Secrets Manager and configured ECS to retrieve the password at task startup. The ECS execution role's secret access is scoped to the RDS-managed secret. |
| F-08 | Database security group allowed PostgreSQL from any IPv4 address | The database was exposed to connection attempts from arbitrary IPv4 sources. | Restricted PostgreSQL ingress to the ECS pipeline security group. |
| F-09 | RDS was publicly accessible, unencrypted, had no automated backup retention, and lacked deletion protection | Increased risk of unauthorized access, data loss, and accidental deletion. | Set the instance to private, enabled storage encryption, configured seven-day backup retention, enabled deletion protection, and required a final snapshot on destruction. Validate subnet routing and recovery requirements before rollout. |
| F-10 | GitHub OIDC trust policy allowed a broad repository pattern | Other repositories could potentially assume the deployment role. | Restricted the trust condition to an exact repository and branch. Supply the intended repository and branch values during validation. |
| F-11 | GitHub deployment role had AdministratorAccess | A compromised workflow could gain excessive AWS privileges. | Removed AdministratorAccess. A least-privilege deployment policy is still required before deployments can work. |
| F-12 | CI used a long-lived IAM user and Terraform-managed access key, with credential outputs | Long-lived credentials could be leaked or misused and could provide broad access. | Removed the legacy IAM user, access-key, administrator-policy, and credential-output resources from the Terraform configuration. Inventory and migrate existing consumers, revoke old keys, and decommission the user only after verifying that no pipelines depend on it. |
| F-13 | ECS container used debug-level logging | Extracted clinical text or other sensitive details could be written to logs. | Changed `LOG_LEVEL` to `INFO`. Review application logging to ensure that clinical document contents, credentials, and other sensitive data are not logged. |

## Important Residual Risks and Follow-up Work

1. **Validate the Terraform configuration.** Run formatting and validation in a safe local environment. Do not apply changes to AWS as part of this assignment.
2. **Complete GitHub deployment permissions.** Review the real workflow and define a least-privilege IAM policy before enabling deployment.
3. **Restore partner upload access safely.** The previous raw-bucket policy was removed intentionally. Confirm the approved partner access method and test each partner's prefix-scoped permissions before production rollout.
4. **Review the database identity model.** The ECS task currently uses the RDS master username. Prefer a separate application database user with only the permissions required by the parser.
5. **Confirm networking.** Verify that the supplied database subnets are private and span at least two Availability Zones. Review the ECS task networking and outbound access requirements.
6. **Review audit-log protection.** Assess bucket encryption, versioning, retention, access restrictions, and whether additional immutability controls are required.
7. **Review log retention.** Configure an appropriate retention period for the ECS CloudWatch log group and ensure sensitive data is not logged.
8. **Confirm operational settings.** Validate RDS backup and restore procedures, final snapshot naming, maintenance windows, and image vulnerability response procedures.

## Validation Status

The changes above describe the current Terraform configuration and intended remediation. They should not be interpreted as proof that Terraform validation, AWS policy simulation, integration tests, or a production deployment have succeeded.

No AWS deployment was performed as part of this assignment.
