# Grafana Alloy Agent Deployment

An Ansible role plus a Jenkins pipeline that installs and configures Grafana Alloy on Linux and Windows servers. `config.alloy` is downloaded from your config service on **every** run, so server-side configuration changes are picked up without changing this repository.

A run does four things:

1. **Installs** the requested Alloy version — `.deb` / `.rpm` on Linux, `.exe` on Windows.
2. **Configures** the agent — downloads `config.alloy`, validates it, then replaces the live file.
3. **Restarts and enables** the Alloy service.
4. **Verifies** the agent answers on `http://127.0.0.1:<alloy_http_port>/-/ready` and reports the installed version.

Linux runs also grant log-file ACLs, add supplementary groups and write systemd resource limits. An optional exporter artifact can be installed on both platforms.

There is a single entry point, `ansible/playbooks/deploy_alloy.yml`. It holds a Linux play, a Windows play, and an imported on-prem play that runs only when `deploy_onprem=true`.

---

## Contents

1. [Repository layout](#1-repository-layout)
2. [Prerequisites](#2-prerequisites)
3. [Configuration](#3-configuration)
4. [Running the playbook](#4-running-the-playbook)
5. [Jenkins pipeline](#5-jenkins-pipeline)
6. [Optional exporter](#6-optional-exporter)
7. [Troubleshooting](#7-troubleshooting)
8. [Reference: sample Alloy config](#8-reference-sample-alloy-config)

---

## 1. Repository layout

```text
grafana-alloy-monitoring/
├─ ansible/
│  ├─ ansible.cfg                          # Ansible settings (portable roles_path)
│  ├─ requirements.yml                     # Collections: ansible.windows, ansible.posix, amazon.aws
│  ├─ .ansible-lint                        # Lint profile and deliberate exclusions
│  ├─ inventory/
│  │  ├─ dev/hosts.ini                     # AWS SSM inventory (placeholders)
│  │  ├─ staging/hosts.ini                 # AWS SSM inventory (placeholders)
│  │  ├─ prod/hosts.ini                    # AWS SSM inventory (placeholders)
│  │  └─ onprem/hosts.ini                  # On-prem inventory (linux_servers)
│  ├─ group_vars/all.yml                   # Environment overrides only (empty by default)
│  ├─ playbooks/deploy_alloy.yml           # Single entry point
│  └─ roles/alloy_agent/
│     ├─ defaults/main.yml                 # Canonical variable catalogue
│     ├─ vars/                             # Per-OS path maps
│     ├─ tasks/main.yml                    # Install → exporter → configure → service → verify
│     ├─ tasks/exporter/                   # Shared exporter flow
│     ├─ tasks/configure/                  # Config validation and Linux post-config
│     ├─ tasks/deploy_alloy_onprem.yml     # On-prem play (imported by the playbook)
│     ├─ handlers/main.yml                 # Restart handler
│     └─ meta/                             # Galaxy metadata and argument_specs.yml
├─ configs/stage/                          # Reference Alloy config sample (not deployed)
├─ packages/                               # Optional local .deb/.rpm/.exe packages
├─ Jenkinsfile                             # Declarative pipeline
└─ README.md
```

| Path | Notes |
|------|-------|
| `defaults/main.yml` | The only place default values are defined. |
| `group_vars/all.yml` | Intended for environment overrides only; ships as `{}` with commented examples. |
| `packages/` | Empty except `.gitkeep`. Populate it for offline or on-prem runs. |
| `configs/stage/` | A reference sample; the role never deploys it. |

---

## 2. Prerequisites

### 2.1 Control node (where Ansible runs)

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| Ansible Core | 2.16 | 2.18 | `ansible.windows >= 3.2.0` requires 2.16+ |
| Python | 3.10 | 3.11 | Required by ansible-core 2.16 |
| boto3 / botocore | current | current | Used by the `amazon.aws.aws_ssm` connection |
| AWS CLI | v2 | current | For controller credentials |
| ansible-lint | 6.0 | current | `pip3 install ansible-lint` |
| Git | 2.30 | current | SCM checkout |

Verify:

```bash
ansible --version                    # 2.16+
python3 --version                    # 3.10+
ansible-galaxy collection list       # ansible.windows, ansible.posix, amazon.aws
ansible-lint --version               # 6.0+
```

### 2.2 Jenkins

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Jenkins | 2.375 LTS | 2.426 LTS |
| Java | 11 | 17 |

Plugins actually used by the `Jenkinsfile`:

| Plugin | Purpose |
|--------|---------|
| Pipeline (with Pipeline: Declarative) | `pipeline {}` syntax and core steps |
| Git | Checkout of the repository and `Jenkinsfile` |
| Email Extension | `emailext()` in the `post` block |
| Timestamper | `timestamps()` |
| Build User Vars *(optional)* | `BUILD_USER_ID` in the notification email |

No `sshagent` or credential binding is required: the shipped inventories connect through AWS SSM using the agent's own AWS credentials.

### 2.3 Target hosts

Linux:

| OS | Versions | Package manager |
|----|----------|-----------------|
| Ubuntu | 20.04, 22.04, 24.04 LTS | `apt` |
| Debian | 11, 12 | `apt` |
| RHEL / Rocky / AlmaLinux | 8.x, 9.x | `dnf` / `yum` |
| CentOS Stream | 8, 9 | `dnf` / `yum` |
| Amazon Linux | 2, 2023 | `dnf` / `yum` |

Requirements: Python 3, `sudo` or root, systemd, and `ansible.posix` on the controller for the ACL tasks.

Windows:

| OS | Versions |
|----|----------|
| Windows Server | 2019, 2022 |
| Windows 10 / 11 Pro or Enterprise | 1809+ |

Requirements: PowerShell 5.1+, .NET Framework 4.7.2+, Administrator rights, and an execution policy of `RemoteSigned` or `Unrestricted`.

> **SUSE is not supported.** The role asserts Debian, RedHat, Amazon or Windows and stops on anything else.

### 2.4 Connectivity (AWS SSM)

The shipped inventories use the `amazon.aws.aws_ssm` connection plugin, not SSH or WinRM. Requirements:

| Requirement | Details |
|-------------|---------|
| Controller packages | `boto3`, `botocore`, AWS CLI v2 with working credentials |
| Collection | `amazon.aws >= 8.0.0` (from `requirements.yml`) |
| Target host | SSM Agent running, instance profile with `AmazonSSMManagedInstanceCore` |
| S3 bucket | `ansible_aws_ssm_bucket_name` must exist in the same region (used for file transfer) |
| Windows shell | `ansible_shell_type=powershell` |
| IAM permissions | `ssm:StartSession`, `ssm:SendCommand`, `ssm:GetCommandInvocation`, `s3:PutObject`, `s3:GetObject` |

The Session Manager plugin binary is **not** required — Ansible talks to the SSM API through boto3.

Example inventory entry (`ansible/inventory/dev/hosts.ini`):

```ini
[linux_hosts]
ubuntu-linux-dev-01 ansible_host=10.10.11.11 ansible_connection=amazon.aws.aws_ssm ansible_aws_ssm_instance_id=i-xxxxxxxxxxxxxxxxx ansible_aws_ssm_region=<aws-region> ansible_aws_ssm_bucket_name=<ssm-transfer-bucket>

[windows_hosts]
windows-dev-01 ansible_host=10.10.11.21 ansible_connection=amazon.aws.aws_ssm ansible_aws_ssm_instance_id=i-xxxxxxxxxxxxxxxxx ansible_aws_ssm_region=<aws-region> ansible_aws_ssm_bucket_name=<ssm-transfer-bucket> ansible_shell_type=powershell
```

SSH and WinRM also work if you write your own inventory entries, for example:

```ini
prod-db-01 ansible_host=10.10.11.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become=true ansible_become_method=sudo
```

Before running the pipeline, confirm access from the controller:

```bash
aws sts get-caller-identity
ansible-inventory -i ansible/inventory/dev/hosts.ini --list
```

> All shipped inventories contain **commented-out placeholders**. Empty groups are safe: Ansible prints `no hosts matched` and the run succeeds without changes. Uncomment and fill in your hosts before deploying.

---

## 3. Configuration

### 3.1 Where settings live

| Layer | File | Purpose |
|-------|------|---------|
| Defaults | `ansible/roles/alloy_agent/defaults/main.yml` | Canonical values for every platform and the on-prem play |
| Overrides | `ansible/group_vars/all.yml` | Per-environment overrides only; do not repeat defaults |
| Per run | `-e` / `EXTRA_VARS` | Wins over everything, including `vars_files` |

The on-prem play loads the same `defaults/main.yml` through `vars_files`, so there is one catalogue for both modes. Because `vars_files` outrank inventory `group_vars`, use `-e` (or `EXTRA_VARS` in Jenkins) for per-run overrides.

### 3.2 Package sources

Exactly one source is used per run, chosen by two variables:

| `alloy_package_local_dir` | `artifact_base_url` | Source |
|---------------------------|---------------------|--------|
| set | any | Local copy from `packages/` (`copy` / `win_copy`), no download |
| empty | set | Bitbucket, with `?at=<artifact_branch>` and a Bearer token |
| empty | empty | `<alloy_download_base_url>/<alloy_download_version_prefix><alloy_version>/` |

Layouts:

```text
# Generic (Artifactory / Nexus / JFrog / GitHub)
<alloy_download_base_url>/v<alloy_version>/alloy-<version>-1.<arch>.rpm
<alloy_download_base_url>/v<alloy_version>/alloy-installer-windows-amd64.exe

# Bitbucket
<artifact_base_url>/<alloy_version>/<package>?at=<artifact_branch>
<artifact_base_url parent>/alloy-installer-windows-amd64.exe?at=<artifact_branch>
```

The generic base URL defaults to `https://github.com/grafana/alloy/releases/download`. Set `alloy_download_version_prefix: ""` for a mirror that does not use the `v` prefix.

`alloy_package_local_dir` must be an **absolute path on the controller**; relative paths resolve against the playbook directory, not your shell.

### 3.3 Config download

`config.alloy` is fetched from the config service on every run:

```text
GET <config_base_url_linux|config_base_url_windows>?server=<hostname>
Header: token: <alloy_static_key>: <hostname reversed>
```

The response is written to `config.alloy.new`, checked for an empty body or a `{"error"` response, and validated with `alloy validate`. Only then does it replace the live file, so a bad response leaves the running config untouched. The service is restarted on every run.

Both URLs default to `https://your-config-service.example.com/...` placeholders and must be replaced.

### 3.4 Secrets

No Ansible Vault is used. Secrets come from Jenkins or from a git-ignored vars file.

| Variable | When required |
|----------|---------------|
| `alloy_static_key` | Always (Linux and Windows) — the config service token |
| `bitbucket_token` | When `artifact_base_url` is set |
| `repo_token` | Optional exporter; defaults to `bitbucket_token` |

`secrets.yml` for local runs:

```yaml
# secrets.yml - never commit this file
alloy_static_key: "<static-key>"
bitbucket_token: "<bitbucket-token>"
```

```bash
ansible-playbook ... -e @secrets.yml
```

In Jenkins, provide the same values as credentials or environment variables that reach the playbook as extra vars.

### 3.5 Variables

**Common**

| Variable | Default | Purpose |
|----------|---------|---------|
| `alloy_version` | `1.19.2` | Version to install |
| `alloy_download_base_url` | GitHub releases | Generic package base URL |
| `alloy_package_local_dir` | *(empty)* | Local package directory (absolute path) |
| `artifact_base_url` | *(empty)* | Bitbucket artifact root |
| `artifact_branch` | `master` | Branch for Bitbucket `?at=` |
| `alloy_download_version_prefix` | `v` | Prefix in the generic layout |
| `config_base_url_linux` / `config_base_url_windows` | placeholder | Config-service endpoints |
| `bitbucket_token` / `alloy_static_key` | *(empty)* | Secrets |
| `validate_certs` | `true` | TLS verification for downloads |
| `force_install` | `false` | Reinstall even when the version matches |
| `alloy_download_timeout` | `120` | Download timeout in seconds |
| `install_exporter` | `false` | Enable the exporter flow (section 6) |

**Linux**

| Variable | Default | Purpose |
|----------|---------|---------|
| `alloy_service` | `alloy.service` | systemd unit name |
| `alloy_user` / `alloy_group` | `alloy` | Service account |
| `alloy_config_dir` | `/etc/alloy` | Config directory |
| `alloy_data_dir` | `/var/lib/alloy` | Data directory |
| `alloy_http_port` | `12345` | Health-check port |
| `alloy_package_checksum` | *(empty)* | Optional SHA256 of the `.deb`; the role warns when empty |
| `alloy_disable_gpg_check` | `false` | Keep RPM GPG verification enabled |
| `alloy_binary_path` | `/usr/bin/alloy` | Binary used for `alloy validate` |
| `alloy_log_files` | `/var/log/{messages,secure,syslog}` | Files granted an `r` ACL (missing files are skipped) |
| `alloy_extra_groups` | `oinstall`, `asmadmin`, `adm`, `systemd-journal` | Added when the group exists |
| `alloy_cpu_quota` / `alloy_memory_high` / `alloy_memory_max` | `30%` / `500M` / `700M` | systemd drop-in limits |
| `alloy_env_file` | `/etc/default/alloy` | Created only when missing |
| `alloy_custom_args` | `--server.http.listen-addr=127.0.0.1:12345 --disable-reporting=true` | `CUSTOM_ARGS` content |

**Windows**

| Variable | Default | Purpose |
|----------|---------|---------|
| `alloy_windows_installer_name` | `alloy-installer-windows-amd64.exe` | Installer file name |
| `work_dir` | `C:\Temp\Alloy` | Work directory |
| `alloy_dir` | `C:\Program Files\GrafanaLabs\Alloy` | Install directory |
| `alloy_config_path` | `<alloy_dir>\config.alloy` | Config path |
| `alloy_windows_service` | `Alloy` | Service name |
| `alloy_windows_installer_checksum` | *(empty)* | **Required** for remote installs |
| `alloy_require_windows_installer_checksum` | `true` | Fail when the checksum is missing |

**On-prem**

| Variable | Default | Purpose |
|----------|---------|---------|
| `deploy_onprem` | `false` | Gate for the imported on-prem play |
| `target_group_onprem` | `linux_servers` | Inventory group |
| `alloy_onprem_memory_max` | `{{ alloy_memory_max }}` (`700M`) | Memory cap for the on-prem drop-in |
| `alloy_pkg_dir` | repository `packages/` | Package directory |
| `alloy_support_files_dir` | repository `configs/` | Directory holding `config_alloy.sh` |

### 3.6 Package verification

- **RPM:** GPG checking stays enabled (`alloy_disable_gpg_check: false`) and the role runs `rpm --checksig` before installing, so unsigned or untrusted local RPMs fail even when `localpkg_gpgcheck` is off. The target must trust the signing key; set `alloy_disable_gpg_check: true` only for unsigned internal RPMs.
- **DEB:** set `alloy_package_checksum` to the package SHA256. The role warns when it is empty.
- **Windows:** a remote install requires `alloy_windows_installer_checksum` (bare SHA256 or `sha256:<digest>`); the file is checked with `Get-FileHash`. A local `packages/` copy does not require it.

Checksums belong to the role and inventory layer (`group_vars/all.yml` or the inventory). The `Jenkinsfile` deliberately has no checksum parameter.

### 3.7 Linux service flags

The packaged systemd unit reads `EnvironmentFile=-/etc/default/alloy` and expands `$CUSTOM_ARGS`:

```bash
# /etc/default/alloy
CUSTOM_ARGS="--server.http.listen-addr=127.0.0.1:12345 --disable-reporting=true"
```

The role creates this file **only when it is missing**, so local edits survive every run. Delete it and re-run to recreate it from `alloy_custom_args`.

Windows stores the command line in the service registration instead. To apply the same flags, update `ImagePath` once per host:

```powershell
$bin = 'C:\Program Files\GrafanaLabs\Alloy\alloy.exe'
$cfg = 'C:\Program Files\GrafanaLabs\Alloy\config.alloy'
sc.exe config Alloy binPath= "`"$bin`" run --server.http.listen-addr=127.0.0.1:12345 --disable-reporting=true `"$cfg`""
Restart-Service Alloy
```

The installer rewrites the registration on upgrade, so re-apply the flags afterwards. The role does not modify `ImagePath` because an upgrade would overwrite it.

---

## 4. Running the playbook

### 4.1 Setup (once)

```bash
cd grafana-alloy-monitoring
mkdir -p packages

# Always point Ansible at the repo config, otherwise the role is not found.
export ANSIBLE_CONFIG=ansible/ansible.cfg
export INV=ansible/inventory/dev/hosts.ini
export PB=ansible/playbooks/deploy_alloy.yml
```

Create `secrets.yml` as shown in section 3.4. The config-service URLs in `defaults/main.yml` are placeholders, so set the real endpoints in `ansible/group_vars/all.yml` before the first run.

The commands below use the three variables above. If you prefer, paste the real paths inline instead.

### 4.2 Linux hosts

**A. Artifacts already in the local `packages/` directory** (no download):

```bash
ansible-playbook -i $INV $PB -e @secrets.yml \
  -e "alloy_version=1.19.2" \
  -e "alloy_package_local_dir=$PWD/packages" \
  --limit linux_hosts
```

**B. Artifacts in Bitbucket** (needs `bitbucket_token`):

```bash
ansible-playbook -i $INV $PB -e @secrets.yml \
  -e "alloy_version=1.19.2" \
  -e "artifact_base_url=https://your-bitbucket.example.com/rest/api/1.0/projects/PROJECT/repos/REPO/raw/alloy-linux" \
  --limit linux_hosts
```

**C. Artifacts from Artifactory / Nexus / JFrog** (or any generic mirror):

```bash
ansible-playbook -i $INV $PB -e @secrets.yml \
  -e "alloy_version=1.19.2" \
  -e "alloy_download_base_url=https://your-artifactory.example.com/artifactory/grafana-alloy" \
  --limit linux_hosts
```

For GitHub, which is the default, use command **C** without the `alloy_download_base_url` line.

### 4.3 Windows hosts

The same three sources, with `--limit windows_hosts`. A remote install (B and C) also requires `alloy_windows_installer_checksum`; set it in `ansible/group_vars/all.yml` before running.

**A. Installer already in the local `packages/` directory** (no checksum needed):

```bash
ansible-playbook -i $INV $PB -e @secrets.yml \
  -e "alloy_version=1.19.2" \
  -e "alloy_package_local_dir=$PWD/packages" \
  --limit windows_hosts
```

**B. Installer in Bitbucket** (taken from the parent folder of `artifact_base_url`):

```bash
ansible-playbook -i $INV $PB -e @secrets.yml \
  -e "alloy_version=1.19.2" \
  -e "artifact_base_url=https://your-bitbucket.example.com/rest/api/1.0/projects/PROJECT/repos/REPO/raw/alloy-linux" \
  --limit windows_hosts
```

**C. Installer from Artifactory / Nexus / JFrog** (or GitHub):

```bash
ansible-playbook -i $INV $PB -e @secrets.yml \
  -e "alloy_version=1.19.2" \
  -e "alloy_download_base_url=https://your-artifactory.example.com/artifactory/grafana-alloy" \
  --limit windows_hosts
```

The installer name is `alloy-installer-windows-amd64.exe`, expected at `<base>/v<version>/` for the generic layout.

> Only **one** source flag per run. Precedence is local folder → Bitbucket → generic base URL (section 3.2).

### 4.4 Limiting a run

`deploy_alloy.yml` contains all three plays. `--limit` selects the hosts; `deploy_onprem` decides whether the on-prem play does any work.

| Goal | Inventory | Extra flags |
|------|-----------|-------------|
| Linux only | `inventory/dev/hosts.ini` | `--limit linux_hosts` |
| Windows only | `inventory/dev/hosts.ini` | `--limit windows_hosts` |
| Linux + Windows | `inventory/dev/hosts.ini` | `--limit linux_hosts:windows_hosts` |
| One host | any | `--limit <host-name>` |
| On-prem only | `inventory/onprem/hosts.ini` | `-e "deploy_onprem=true" --limit linux_servers` |

Useful flags for any command:

| Flag | Effect |
|------|--------|
| `--check --diff` | Dry run; install and download are skipped |
| `-e "validate_certs=false"` | Internal CA not yet trusted on the target |

### 4.5 On-prem

The on-prem play lives in `ansible/roles/alloy_agent/tasks/deploy_alloy_onprem.yml` and is imported by the playbook. It is skipped unless `deploy_onprem=true`, so a normal Linux/Windows run is unaffected.

It uses the local delivery flow — a package from `packages/` and `config_alloy.sh` from `configs/` — and ignores `artifact_base_url`, `bitbucket_token`, `config_base_url_*` and `alloy_static_key`.

```bash
ansible-playbook -i ansible/inventory/onprem/hosts.ini $PB \
  -e "deploy_onprem=true" \
  -e "alloy_version=1.19.2"
```

The on-prem play uses its own inventory, not `$INV`.

Add the exporter flags from section 6 if an exporter is needed.

Required files (the defaults already point at the repository copies):

| File | Purpose |
|------|---------|
| `packages/alloy-<version>-1.<arch>.rpm` or `.deb` | Package copied to the target |
| `configs/config_alloy.sh` | Downloads `config.alloy` on the target |

> **`configs/config_alloy.sh` is not included in this repository.** Supply the script that downloads `config.alloy` from the config service and place it at `configs/config_alloy.sh`, or point `alloy_support_files_dir` at the directory that contains it. The play fails fast with a clear message when the script or the package is missing.

Supported families: RedHat and Debian. The on-prem play verifies the service and HTTP endpoint itself, so the separate `--tags verify` stage is not used.

---

## 5. Jenkins pipeline

### 5.1 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `PLAYBOOK` | Choice | `role` | `role` = Linux/Windows roles with `inventory/<ENVIRONMENT>/hosts.ini`; `onprem` = on-prem play with `inventory/onprem/hosts.ini` |
| `ENVIRONMENT` | Choice | `dev` | Role deploy only: `dev`, `staging` or `prod`. On-prem always uses the on-prem inventory |
| `ALLOY_VERSION` | String | `1.19.2` | Version to install; applies to both modes |
| `ARTIFACTORY_URL` | String | GitHub releases | Role deploy only: generic package base URL |
| `HOST_LIMIT` | String | *(empty)* | Ansible `--limit` pattern; applies to both modes |
| `DEPLOY_SERIAL` | String | `50%` | Role deploy only: rolling deploy batch size |
| `DRY_RUN` | Boolean | `false` | `--check --diff` for role mode; rejected for on-prem |
| `EXPORTER_NAME` | String | *(empty)* | Enables the exporter flow in both modes |
| `EXPORTER_VERSION` | String | *(empty)* | Required when `EXPORTER_NAME` is set |
| `EXPORTER_REPO_URL` | String | *(empty)* | Required when `EXPORTER_NAME` is set (the role default is a placeholder) |
| `REPO_TOKEN` | Password | *(empty)* | Exporter token; masked in the console |
| `EXTRA_VARS` | String | *(empty)* | Extra vars applied last, so they override every parameter above |
| `EMAIL_RECIPIENTS` | String | *(empty)* | Notification recipients |

`alloy_static_key` and `bitbucket_token` are not parameters: supply them as credentials or environment variables that reach the playbook as extra vars. The per-OS config URLs are set in `defaults/main.yml`.

### 5.2 Stages

| Stage | When | What it does |
|-------|------|--------------|
| Parameter Validation | Always | Requires `ALLOY_VERSION`; requires `EXPORTER_VERSION` and `EXPORTER_REPO_URL` when `EXPORTER_NAME` is set; rejects `DRY_RUN` for on-prem |
| Setup Ansible Collections | Always | `ansible-galaxy collection install -r requirements.yml` |
| Ansible Lint & Syntax Check | Always | `ansible-lint` plus `--syntax-check`; a failure stops the build (30-minute timeout) |
| Approval | `PLAYBOOK == 'onprem'` or `ENVIRONMENT == 'prod'` | Manual gate **before** deployment. On-prem always requires approval because it has a single inventory. Waits up to 24 hours |
| Deploy Alloy | Always | Runs the playbook with the inventory for the selected mode. Every value is shell-quoted; `REPO_TOKEN` and `EXTRA_VARS` are masked and xtrace is disabled (2-hour timeout) |
| Post-Deploy Verification | Role mode only, not `DRY_RUN` | Re-runs with `--tags verify` against the same `HOST_LIMIT` subset. The recap is embedded in the notification email |

The pipeline timeout is 26 hours so the 24-hour approval window can complete; the work stages carry their own shorter timeouts. Notifications always send a status email with target, version and the verification recap.

### 5.3 Creating the job

1. Install the plugins from section 2.2.
2. Give the agent AWS access: attach an IAM role with SSM and S3 permissions (recommended), or bind an AWS credential.
3. **New Item** → **Pipeline** → in the Pipeline section choose **Pipeline script from SCM**, set the repository URL and `Script Path = Jenkinsfile` → **Save**.
4. **Build with Parameters**, fill in the values, and build.
5. Watch the console; for `prod` or `onprem` an approval prompt appears before deployment.

---

## 6. Optional exporter

Set `install_exporter: true` (or `EXPORTER_NAME` in Jenkins) to install an exporter artifact on Linux and Windows. The role downloads the ZIP with a Bearer token, extracts it, locates the JAR, writes the default config, and records `current.version`.

| Variable | Default | Purpose |
|----------|---------|---------|
| `install_exporter` | `false` | Enable the flow |
| `exporter_name` | *(empty)* | e.g. `jmx-exporter`; lowercased for paths |
| `exporter_version` | *(empty)* | e.g. `1.5.0` |
| `repo_token` | `{{ bitbucket_token }}` | Repository token |
| `exporter_repo_root_url` | placeholder | Artifact root; must be replaced |
| `exporter_repo_branch` | `master` | Branch appended as `?at=` |
| `exporter_base_dir` | per-OS default | `/opt/grafana-alloy/exporters` or `C:\ProgramData\GrafanaLabs\Alloy\exporters` |
| `exporter_cleanup_artifact` | `true` | Remove the ZIP after extraction |
| `exporter_overwrite_config` | `false` | Keep local edits to the config file |

Naming: `jmx-exporter` uses `jmx_prometheus_javaagent-<version>.zip` and `jmx-config.yaml`; any other name uses `<name>-<version>.zip` and `<name>-config.yaml`.

```bash
ansible-playbook ... -e "install_exporter=true" -e "exporter_name=jmx-exporter" -e "exporter_version=1.5.0"
```

The exporter step is tagged `exporter`, so `--tags verify` does not re-download it.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Alloy did not become ready` | Service did not start, or the config is invalid | `journalctl -u alloy` (Linux) or Event Viewer → Applications and Services Logs → Grafana Alloy (Windows) |
| `Unsupported OS` | Host is not Debian, RedHat, Amazon or Windows | Use a supported family; SUSE is not supported |
| Permission denied | Missing `sudo`/root (Linux) or Administrator (Windows) | Fix the account privileges |
| `401` / `403` downloading a package | `bitbucket_token` missing or invalid | Set the token in Jenkins or `secrets.yml` |
| TLS error downloading package or config | Internal CA not trusted on the target | Install the CA, or set `validate_certs: false` temporarily |
| `alloy_static_key` / `config_base_url_*` required | The config download is always on | Provide `alloy_static_key` and replace the placeholder URLs |
| `alloy_windows_installer_checksum is required` | Remote Windows install without a checksum | Set the SHA256, or `alloy_require_windows_installer_checksum: false` for a lab |
| RPM signature check failed | The target does not trust the signing key | Import the key, or set `alloy_disable_gpg_check: true` for unsigned internal RPMs |
| Alloy cannot read logs | ACLs not applied | Ensure `ansible.posix` is installed and re-run the configure steps |
| Service fails after a config download | The config service returned an invalid config | Check `journalctl -u alloy`; the previous config was kept |
| On-prem: package not found | `packages/` has no matching file | Add `alloy-<version>-1.<arch>.rpm`/`.deb`, or override `alloy_version` |
| On-prem: `config_alloy.sh not found` | The support script is missing | Add `configs/config_alloy.sh` or set `alloy_support_files_dir` |
| `no hosts matched` | The inventory group is empty | Expected; uncomment and fill in hosts |

---

## 8. Reference: sample Alloy config

`configs/stage/alloy-windows-vm-oracle-mssql.alloy` is a reference sample that collects Windows VM metrics plus Oracle and SQL Server metrics and remote-writes to Grafana Cloud.

It is **not deployed**. The role downloads the live `config.alloy` from the config service on every run, so this file only documents an example configuration.
