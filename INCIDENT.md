# Security Incident Response: Suspicious IAM Activity and RDS Snapshot Sharing

## 1. Executive Summary

GuardDuty generated a low-severity Discovery finding involving unusual activity associated with the `ci-deployer` IAM user. The activity originated from an unusual IP address in the Netherlands (`203.0.113.45`) at approximately 02:47–02:48 UTC.

Subsequent activity included creation of an IAM user named `svc-backup-02`, attachment of `AdministratorAccess`, creation of an access key, creation of an RDS snapshot named `acme-clinical-prod-0414`, and sharing of that snapshot with AWS account `444455556666`.

This sequence is suspicious and may indicate compromised CI/CD credentials and attempted unauthorized access to clinical database data.

**Confirmed from the supplied incident details:** an RDS snapshot was created and its restore attribute was shared with another AWS account.

**Not confirmed from the supplied details:** whether the recipient account restored the snapshot, accessed its contents, or obtained protected health information (PHI).

Treat this as a potential data exposure incident until the investigation establishes the scope.

## 2. Timeline

All times below are UTC, as reported in the incident details.

| Time | Observed activity | Security significance |
|---|---|---|
| 02:47–02:48 | GuardDuty reports unusual activity associated with `ci-deployer`, from `203.0.113.45`. | Potential credential compromise; validate against expected CI/CD activity. |
| After the initial activity | IAM user `svc-backup-02` is created. | Potential persistence through a new identity. |
| After user creation | `AdministratorAccess` is attached and an access key is created for `svc-backup-02`. | Broad privileges and persistent credentials increase the potential impact. |
| 03:06 | Snapshot `acme-clinical-prod-0414` is created. | Potential preparation for database data extraction. |
| 03:41 | Snapshot restore access is shared with account `444455556666`. | Potential unauthorized cross-account access to sensitive data. |
| Later | `DescribeRegions` is called. | May indicate reconnaissance; investigate related activity and identities. |

The precise timestamps of the IAM user creation, policy attachment, and access-key creation should be established from CloudTrail records.

## 3. Potential Impact

- Unauthorized control of AWS resources if the `ci-deployer` credentials were compromised.
- Persistence through the newly created IAM identity and access key.
- Potential unauthorized access to a database snapshot containing sensitive clinical information.
- Possible regulatory, contractual, and privacy implications if PHI was accessed or disclosed.
- Risk of additional infrastructure changes, data exfiltration, or destruction.

The shared snapshot is evidence of a potential exposure path, not proof that the snapshot was restored or its contents accessed. Determine actual access and data exposure from recipient-account activity and other available evidence.

## 4. First 60 Minutes: Response Plan

### Minutes 0–10: Declare and contain

1. Open a security incident and notify the incident commander and security operations team.
2. Validate the GuardDuty finding and correlate it with CloudTrail events.
3. Preserve relevant logs and record the finding ID, event IDs, timestamps, source IP, principal ARN, and affected resources.
4. Disable or revoke the suspected compromised `ci-deployer` credentials using the approved emergency procedure. Coordinate with CI/CD owners to avoid uncontrolled production disruption.
5. Contain the newly created `svc-backup-02` identity: disable or revoke its access key and remove its ability to perform further actions, using an approved containment sequence.
6. Check for additional access keys, role sessions, users, policies, or other persistence mechanisms created during the suspicious activity.

Do not delete identities or resources before preserving relevant evidence where operationally feasible.

### Minutes 10–20: Secure the snapshot

1. Inspect the permissions and restore attributes of `acme-clinical-prod-0414`.
2. Remove unauthorized cross-account snapshot sharing after recording the existing permissions and obtaining the appropriate incident-response approval.
3. Determine whether the recipient account created a copy or restored the snapshot.
4. Review snapshot encryption and
