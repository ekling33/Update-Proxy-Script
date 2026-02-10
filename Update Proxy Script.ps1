Blue Prism addressed CVE-2019-11875 and CVE-2022-36115 through specific upgrades that align with our move from 6.10.1 to 7.1.2.

CVE-2019-11875 Fix
This vulnerability enabled abuse of the application for fraud or unauthorized access with a valid user account. Blue Prism resolved it in version 6.5 by implementing code obfuscation, which complicates reverse engineering and exploitation. Since 6.10.1 (post-6.5) already included this, the upgrade reinforces the protection layer.

CVE-2022-36115 Fix
Affects Blue Prism Enterprise 6.0 through 7.0.1, allowing authenticated users in misconfigured environments to reverse engineer software and bypass access controls on the setValidationInfo function, risking hidden malicious code. Blue Prism fixed it in 7.1.1 release notes, confirming mitigation via server permissions and communication improvements in major releases like 7.x. Upgrading to 7.1.2 fully addresses it as recommended.
