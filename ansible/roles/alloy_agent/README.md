# alloy_agent

Installs and configures [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
on Debian/Ubuntu, RHEL/Rocky/Alma, Amazon Linux and Windows.

- Installs Alloy from GitHub, a Bitbucket/Artifactory mirror, or a local folder.
- Downloads `config.alloy` from the config service **on every run**.
- Restarts Alloy **on every run**, so config changes on the server are picked up.
- Optionally installs a JMX (or other) exporter beside Alloy.

## Requirements

- Ansible 2.14 or newer.
- Collections: `ansible.posix`, `ansible.windows`.
  Install them with `ansible-galaxy collection install -r requirements.yml`.
- A config-service endpoint and a static key (see below).

## Minimal example

```yaml
- hosts: linux_hosts
  become: true
  roles:
    - role: alloy_agent
      vars:
        alloy_version: "1.19.2"
        config_base_url_linux: "https://config.example.com/linux/download-config/v2"
        alloy_static_key: "{{ lookup('env', 'ALLOY_STATIC_KEY') }}"
```

Windows uses the same role with `config_base_url_windows`.

## The only variables you must set

| Variable | Why |
|---|---|
| `config_base_url_linux` or `config_base_url_windows` | Where `config.alloy` is downloaded from |
| `alloy_static_key` | Token for the config service |
| `bitbucket_token` | Only when `artifact_base_url` is set |

Everything else has a working default. Run `ansible-doc alloy_agent` for the
full list; the contract lives in `meta/argument_specs.yml`.

## Package sources

Choose one, in this order of precedence:

1. `alloy_package_local_dir` — copy from a local folder (testing/air-gapped).
2. `artifact_base_url` — Bitbucket/Artifactory folder, authenticated with
   `bitbucket_token`. The Windows installer is taken from the parent folder.
3. `alloy_download_base_url` — generic versioned layout, default GitHub.

```yaml
# Bitbucket / Artifactory
artifact_base_url: "https://bitbucket.example.com/rest/api/1.0/projects/PRJ/repos/artifacts/raw/alloy-linux"
artifact_branch: "master"
bitbucket_token: "{{ lookup('env', 'BITBUCKET_TOKEN') }}"

# Generic mirror that does not use a "v" prefix
alloy_download_base_url: "https://mirror.example.com/alloy"
alloy_download_version_prefix: ""
```

## Tags

| Tag | What it runs |
|---|---|
| `install` | Package download and install/upgrade |
| `exporter` | Optional exporter install |
| `configure` | Config download, ACLs, groups, `/etc/default/alloy`, systemd drop-in |
| `service` | Enable/start the service |
| `verify` | Readiness and version checks |

Preflight assertions (OS, version, architecture, exporter inputs) are tagged
`always`, so a tagged run still validates them. The source assertions are
scoped: the Bitbucket token check runs with `install`, and the config-service
check runs with `configure`. That keeps `--tags verify` usable without the
download credentials.

## Behaviour worth knowing

- The config file is downloaded to a staging file and validated before it
  replaces the live `config.alloy`. An empty body or a `{"error"` response
  aborts the run and leaves the live file untouched. The staged file is then
  checked with `alloy validate` (`alloy_binary_path`, Windows: `alloy.exe`), so
  a syntactically invalid config fails the run instead of reaching the service.
- ACLs are verified, not assumed: after granting `r` on each existing
  `alloy_log_files` entry and the default `rx` ACL on `/var/log`, the role
  reads them back with `getfacl` and asserts `user:alloy:r--` /
  `default:user:alloy:r-x`. Verification is skipped in check mode.
- RPM GPG verification is on by default (`alloy_disable_gpg_check: false`) for
  both the role's `yum` install and the on-prem `dnf` install. The role also
  runs `rpm --checksig` before install, so an unsigned or untrusted local RPM
  fails even when `localpkg_gpgcheck` is off. Set `alloy_disable_gpg_check` to
  `true` only when the internal RPM is unsigned.
- A remote Windows install requires `alloy_windows_installer_checksum`
  (`alloy_require_windows_installer_checksum: true` by default). The SHA256 is
  verified with `Get-FileHash`; a bare digest or `sha256:<digest>` is accepted.
  Set the require flag to `false` only for a lab run. The Linux package uses
  the optional `alloy_package_checksum`; the role warns when it is empty.
- On Windows the service is restarted even when the download fails, so a failed
  run never leaves Alloy stopped.
- `exporter_overwrite_config` defaults to `false`: a local edit to
  `jmx-config.yaml` survives the next run.
- `/etc/default/alloy` is created with
  `CUSTOM_ARGS="--server.http.listen-addr=127.0.0.1:12345 --disable-reporting=true"`
  only when it is missing; an existing file is never overwritten. Windows has
  no `/etc/default`; see the root README for the `sc.exe config` equivalent.
- On-prem deployments use `tasks/deploy_alloy_onprem.yml`, imported by
  `playbooks/deploy_alloy.yml` and gated by `deploy_onprem`. That path installs
  from `alloy_pkg_dir` and downloads the config with
  `alloy_support_files_dir/config_alloy.sh`.
- The role and the on-prem play share `tasks/exporter/install_linux.yml`,
  `tasks/exporter/install_windows.yml`, `tasks/configure/validate_config.yml`
  and `tasks/configure/linux_post.yml`, so config validation, ACLs, the systemd
  drop-in and the exporter flow cannot drift between the two paths.
- `alloy_memory_max` defaults to `700M`; the on-prem play uses
  `alloy_onprem_memory_max`, which defaults to the same value.

## Testing

```bash
ansible-playbook -i inventory/hosts.ini playbooks/deploy_alloy.yml \
  --check --diff --limit linux_hosts
```

Use `alloy_package_local_dir` plus a local `config.alloy` service stub for an
offline test.
