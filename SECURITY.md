# Security

## Distribution and support

The 1.0.29 Mac disk image is Developer ID signed and notarized by Apple; the 1.0.29 Windows installer is not publisher-signed. Check the [release notes](https://github.com/asetho/ChatGPT-Usage/releases) for the signing status of the package you download. No claim is made that a source review, successful test run, or checksum proves a binary is safe. Read [UNSIGNED-INSTALL.txt](UNSIGNED-INSTALL.txt) for guidance on unsigned packages. Never disable system-wide protections or bypass malware or organization-policy blocks to run this app.

Security fixes target the latest source and future packages; older installers are not automatically updated. Use only trusted Codex executables. The companion runs that separate program with your user permissions, so its configuration and dependencies are part of your trust decision. The optional Windows prerequisite installer runs code from OpenAI's current HTTPS installer, not a pinned copy audited with this repository.

## Reporting a concern

Use GitHub's **Report a vulnerability** option if it is available for this repository. If it is not available, open an issue asking the maintainer for a private reporting channel, without disclosing exploit details or sensitive data. Do not post authentication files, tokens, raw installer logs, private screenshots, or personal account information publicly.

Include the affected app version, operating system, install source, a concise description of the impact, and safe reproduction steps through the private channel. No response-time commitment or bug-bounty payment is offered.
