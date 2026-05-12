# Add a New Tool to the GUI

This guide describes the standard path for adding another browser or CLI client
to the Flutter launcher.

The goal is that the tool:

- appears in the **Launch** tab,
- participates in the existing `Patch -> Build -> Launch/Run` flow,
- uses the correct CLI or GUI runtime behavior,
- exposes compatibility warnings from its TLS defaults.

## 1. Choose the Integration Path

There are two cases.

| Case | Recommendation |
|---|---|
| The tool uses an existing stack (`nss`, `boringssl`, `openssl`) | Preferred. Usually needs only a descriptor plus build/run scripts. |
| The tool brings a new TLS stack | Requires patch-service and launcher mapping changes. Higher maintenance cost. |

Prefer an existing stack whenever possible.

## 2. Add an App Descriptor

Create:

```text
tools/ja4-spoofer/assets/descriptors/<tool>-<stack>-ja4.yaml
```

Required fields:

- `app_id`
- `metadata.name`
- `build.script`
- `build.built_binary_paths`
- `launch.script`
- `launch.profile_format` (`nss`, `boringssl` or `openssl`)

Useful optional fields:

- `metadata.description`
- `metadata.icon_url`
- `build.ssl_only_script`
- `build.requirements`
- `launch.runtime.kind: cli`
- `launch.runtime.args_placeholder`
- `launch.runtime.args_example`
- `launch.runtime.pass_user_args_after_double_dash`
- `tls_defaults`

### Browser-like Tool

```yaml
app_id: mybrowser-nss-ja4
metadata:
  name: MyBrowser (NSS)
  description: MyBrowser with patched NSS for JA4 control
build:
  script: scripts/build_mybrowser_with_patched_nss.sh
  built_binary_paths:
    - ~/build/mybrowser-ja4/dist/MyBrowser.app/Contents/MacOS/mybrowser
  requirements:
    - name: Xcode CommandLineTools
    - name: Python
      version: "<= 3.12"
launch:
  script: scripts/run_mybrowser_with_ja4.sh
  profile_format: nss
  dump_path: /tmp/nss-ja4-effective.conf
tls_defaults:
  tls_versions: ["1.0", "1.1", "1.2", "1.3"]
  cipher_suites: [4865, 4866, 4867]
  extensions: [0, 10, 11, 13, 43, 45, 51, 65281]
  signature_algorithms: [1027, 1283, 1539, 2052, 2053]
  alpn_protocols: [h2, http/1.1]
```

### CLI Tool

```yaml
app_id: mycli-openssl-ja4
metadata:
  name: mycli (OpenSSL)
build:
  script: scripts/build_mycli_with_openssl.sh
  built_binary_paths:
    - ~/build/mycli-ja4/install/bin/mycli
launch:
  script: scripts/run_mycli_with_ja4.sh
  profile_format: openssl
  runtime:
    kind: cli
    args_placeholder: https://example.com
    args_example: -I https://example.com
    pass_user_args_after_double_dash: true
```

## 3. Add Build and Launch Scripts

Place scripts under `scripts/`:

- `scripts/build_<tool>_with_<stack>.sh`
- `scripts/run_<tool>_with_ja4.sh`

For browser-like tools, a wrapper around `run_browser.sh` is often enough:

```bash
#!/usr/bin/env bash
exec "$(dirname "${BASH_SOURCE[0]}")/run_browser.sh" --browser firefox "$@"
```

If a new browser type is needed, add `scripts/browsers/<tool>.sh` and define the
`BROWSER_*` variables there.

For CLI tools, reuse `scripts/lib/parse_ja4_args.sh`. User-provided arguments
must end up in `JA4_BROWSER_EXTRA_ARGS`. When
`pass_user_args_after_double_dash: true` is set, the launcher passes `--` and
the raw user arguments to the script.

## 4. Avoid UI Hardcoding

The GUI discovers apps from descriptors. A normal tool integration should not
need additional Flutter UI code.

## 5. New TLS Stack Checklist

If `launch.profile_format` is not one of the existing values, update:

- `tools/ja4-spoofer/lib/features/app_launcher/app_launcher_controller.dart`
  — extend the `submoduleName` switch in `AppState` and the profile-args
  mapping in `_profileArgsForApp`.
- `tools/ja4-spoofer/lib/core/services/patch_service.dart` — extend the
  submodule list so the patch-stamp check covers the new stack.

Without these mappings, patch status, patch application and build buttons cannot
work correctly for the new stack.

## 6. Test Checklist

Automated tests to extend as needed:

- `tools/ja4-spoofer/test/core/services/app_descriptor_service_test.dart`
- `tools/ja4-spoofer/test/features/app_launcher/app_launcher_controller_test.dart`

Manual smoke test:

1. Run `flutter run -d macos` or the matching desktop target.
2. Open **Launch**.
3. Confirm the tool appears.
4. Confirm status transitions are correct.
5. Run the main action and verify patch/build/launch behavior.
6. For CLI tools, verify raw user arguments are forwarded correctly.
7. Switch profiles and confirm compatibility warnings still make sense.

## Common Problems

| Symptom | Likely cause |
|---|---|
| Tool does not appear | Invalid YAML or missing descriptor fields |
| Tool stays `Not Built` | `build.built_binary_paths` does not point to the produced binary |
| `unknown option` during launch | Tool arguments were parsed as launcher arguments |
| Patch flow does not run | `profile_format` is missing from the app-to-submodule mapping |

An integration is ready when the descriptor validates, build and run scripts are
stable, smart launch works without UI special cases, and automated plus manual
smoke tests pass.
