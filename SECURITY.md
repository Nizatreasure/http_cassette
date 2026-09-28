# Security policy

HTTP Cassette records and stores HTTP traffic. A cassette can contain credentials, personal information or other sensitive data if sanitisation is incomplete. Review every cassette before sharing or committing it.

## Supported versions

Only the latest released minor version of each package receives security fixes. Users of older minor versions may need to upgrade before receiving a fix.

The packages are released independently, so a report should identify each affected package and version.

## Reporting a vulnerability

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/Nizatreasure/http_cassette/security/advisories/new).

Do not report a vulnerability in a public issue. Do not include real credentials, access tokens, private HTTP traffic, unsanitised cassette files or other sensitive information in a public discussion.

Include the following information where possible:

- the affected package and version;
- a clear description of the problem and its possible impact;
- the configuration and platform involved;
- steps or a minimal example that reproduce the problem;
- whether the issue can expose unsanitised data, access the network during replay or corrupt stored cassettes; and
- any suggested mitigation or fix.

Use synthetic data in examples whenever possible. If real sensitive material is essential to understanding the report, explain that first and wait for instructions before sharing it.

You should receive an acknowledgement within ten working days. The report will be assessed privately, and updates will be provided as the investigation progresses. Please allow time for a fix and coordinated disclosure before publishing details.

## Reporting ordinary bugs

Use [GitHub Issues](https://github.com/Nizatreasure/http_cassette/issues) for bugs that do not have a security impact. Remove credentials, private traffic and other sensitive information before posting.
