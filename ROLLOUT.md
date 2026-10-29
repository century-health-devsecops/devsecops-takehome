# Security Remediation Rollout Plan

## 1. Purpose and Scope

This plan describes how to validate and roll out the Terraform security remediations for the Acme Health clinical document platform.

**Assignment constraint:** No AWS deployment or production infrastructure changes are required or performed for this submission.

The steps below describe a proposed production rollout and must be approved before execution.

## 2. Preconditions

Before any production change:

- [ ] Obtain approval from the infrastructure owner, application owner, and security team.
- [ ] Confirm the target AWS account, region (`us-east-1`), Terraform workspace, and backend state.
- [ ] Verify that the Terraform state bucket is encrypted, access-restricted, versioned, and recoverable.
- [ ] Back up the current Terraform configuration and preserve the current state securely.
- [ ] Review the current infrastructure and Terraform plan for unexpected resource replacements or deletions.
- [ ] Verify private database subnets span at least two Availability Zones.
- [ ] Confirm RDS backup status, restore procedures, and final-snapshot naming.
- [ ] Identify all GitHub Actions workflows that use the legacy `ci-deployer` credentials.
- [ ] Agree on partner upload access requirements before removing or replacing the existing raw-bucket policy.
- [ ] Review the required permissions for the GitHub OIDC deployment role.
- [ ] Schedule an approved change window and define success, abort, and escalation criteria.

## 3. Validation Before Rollout

Perform validation locally or in an approved non-production environment.

1. Run `terraform fmt -check`.
2. Run `terraform init -backend=false` where provider initialization and the available configuration permit it.
3. Run `terraform validate`.
4. Run a static security scan, such as Checkov or tfsec, if available.
5. Review IAM trust policies and permissions for wildcard principals, wildcard resources, and administrative access.
6. Confirm that the ECS task definition references the intended immutable ECR image tag.
7. Verify that the RDS-managed secret reference and ECS execution-role permissions are consistent.
8. Review the planned changes and identify any resource replacements, access interruptions, or destructive operations.

Do not claim validation or scans have passed unless their results have been observed. Do not run `terraform apply` for this assignment.

## 4. Proposed Production Rollout Sequence

### Phase 1 — Audit and logging

- Enable multi-region CloudTrail coverage and log-file validation.
- Confirm CloudTrail can deliver logs to the audit bucket.
- Verify that existing audit logs remain accessible and protected.
- Confirm that the audit bucket cannot be emptied automatically during destruction.

**Validation:** Confirm expected CloudTrail events are delivered and readable by authorized auditors.

### Phase 2 — Storage security

- Enable S3 public-access-block settings on the raw clinical-document bucket.
- Remove the unsafe wildcard-principal policy.
- Implement and test the approved partner access method before resuming uploads.
- Confirm the public-assets bucket remains accessible through the intended CloudFront distribution.

**Validation:** Verify that unauthorized access is denied and each approved partner can access only its authorized prefix.

### Phase 3 — Container image security

- Enable immutable ECR tags and scan-on-push.
- Build and push an image with a unique tag, preferably the Git commit SHA.
- Review image scan findings and remediate critical vulnerabilities according to the approved policy.

**Validation:** Confirm the intended image exists, its tag cannot be overwritten, and scan results are reviewed.

### Phase 4 — Database and application secrets

- Confirm RDS backup and recovery readiness before modifying database settings.
- Validate private subnet routing and security-group connectivity.
- Enable encryption, backup retention, deletion protection, and RDS-managed master credentials as appropriate.
- Configure ECS to retrieve the database password from Secrets Manager using its execution role.
- Review application logging and replace debug logging with an approved production level.
- Plan migration from the RDS master user to a separate least-privilege application database user.

**Validation:** Test database connectivity from the intended ECS tasks, confirm unauthorized sources cannot connect, and verify application health without exposing credentials.

### Phase 5 — IAM and CI/CD

- Configure the GitHub OIDC trust policy for the exact repository and approved branch.
- Create a least-privilege deployment policy based on the actual workflow requirements.
- Test OIDC authentication and deployment in a non-production environment.
- Inventory every consumer of the legacy `ci-deployer` credentials.
- Migrate consumers, revoke old access keys, remove excessive permissions, and decommission the legacy user only after confirming that no dependencies remain.

**Validation:** Confirm approved workflows can obtain short-lived credentials and perform only their authorized actions.

## 5. Rollback and Abort Criteria

Stop the rollout if any of the following occurs:

- Unexpected Terraform resource replacement or deletion.
- Loss of required partner uploads or application connectivity.
- Database connectivity or application health checks fail.
- CloudTrail log delivery fails.
- The deployment workflow cannot authenticate or lacks required scoped permissions.
- A security control causes an unapproved production interruption.

Rollback principles:

1. Pause further changes and notify the change owner.
2. Preserve Terraform plans, logs, CloudTrail evidence, and relevant application diagnostics.
3. Use the approved change procedure to restore the last known-good configuration where safe.
4. Do not reintroduce wildcard bucket policies, public database access, administrator permissions, or exposed long-lived credentials as a quick fix.
5. Restore database data from an approved backup or snapshot only if necessary and under the database recovery procedure.
6. Revalidate security controls and application health before resuming operations.

Some changes, such as credential revocation, snapshot operations, or database replacement, may not be safely reversible. Plan and approve recovery steps before starting.

## 6. Post-Rollout Verification

- [ ] Confirm the RDS instance is private and encrypted.
- [ ] Confirm database access is restricted to approved security groups.
- [ ] Confirm automated backups and deletion protection are enabled.
- [ ] Confirm ECS retrieves the password from Secrets Manager.
- [ ] Confirm S3 public-access-block settings and partner access boundaries.
- [ ] Confirm ECR immutable tags and image scan results.
- [ ] Confirm CloudTrail delivery and log-file validation.
- [ ] Confirm GitHub OIDC trust is restricted to the intended repository and branch.
- [ ] Confirm the deployment role has only approved permissions.
- [ ] Confirm legacy access keys are revoked after migration and the old user has no remaining consumers.
- [ ] Confirm application health, monitoring, alerting, and operational handover.
- [ ] Record the change approval, validation evidence, exceptions, and remaining risks.

## 7. Outstanding Dependencies

The current Terraform configuration does not fully implement every production requirement. Before rollout, the team must complete and review:

- Least-privilege AWS permissions for the GitHub deployment workflow.
- The approved partner upload authorization mechanism.
- A least-privilege application database identity.
- Audit-log retention, access controls, and recovery requirements.
- CloudWatch log retention and sensitive-data logging controls.
- Non-production testing and a reviewed Terraform plan.

No production rollout should proceed until the required approvals, validation, and outstanding dependencies are complete.
