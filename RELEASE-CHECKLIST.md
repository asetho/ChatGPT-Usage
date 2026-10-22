# Unsigned release checklist

This project intentionally uses no paid signing certificates or notarization workflow. Keep that limitation visible; do not describe an unsigned package as OS-verified or instruct users to disable protection globally.

- Confirm the source is distributed under the intended `LICENSE` and that third-party names, trademarks, and artwork are not presented as covered by it.
- Review the intended source revision and run tests. Check repository history and packaged contents for secrets before their first public distribution.
- Update `VERSION` for new package contents. Do not silently replace an existing published version with different bytes.
- Build both platform packages from that exact revision using the repository scripts. Treat any build or checksum-generation failure as a stop condition.
- Confirm the Mac DMG includes `UNSIGNED-INSTALL.txt`, `LICENSE`, the application, and the Applications shortcut. Confirm Windows setup shows the notice before installation and installs both text files.
- Verify each package's `.sha256` file against the finished download. A checksum is not a substitute for publisher signing or an independent security review.
- On clean supported Mac and Windows machines, test the actual downloaded packages: unsigned warning flow, missing CLI, existing CLI, signed-out CLI, optional dependency install/decline/failure, offline refresh, upgrade, startup, and uninstall. Do not disable antivirus or managed-device policies for testing.
- Test **Update now** from an installed older build: download verification, install location, preserved settings and startup choice, restart, and Mac rollback after a failed launch. Publish the matching `.sha256` assets and confirm GitHub reports SHA256 digests for both the installer and checksum assets. Run `dotnet run --project Windows.Tests/UpdateTests.csproj` and, on Mac, `python3 scripts/tests/test-update-helper.py` alongside the app tests. The Windows tests accept `--download-latest` for a public-package download check.
- Confirm which CLI versions work. The optional official Windows CLI installer is mutable; review its behavior and diagnostics before release. If an immutable dependency is required, design and test version/digest verification before claiming reproducibility.
- Include the MIT license, unsigned notice, prerequisites, privacy/security links, known limitations, version, source commit, and matching checksums in release notes. Keep old artifacts distinct from current ones.
- Publish only after explicit release approval. A local build, test pass, or commit is not publication approval.
