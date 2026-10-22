# Grafana Alloy Agent Deployment (Install Only)

> **One‑liner:** *Install Alloy on Linux/Windows servers. No config management - you manage config separately.*

This repository contains a **minimal** Ansible role + Jenkins pipeline that:

1. **Installs** the exact Grafana Alloy version you request (Linux / Windows).
2. **Starts/enables** the Alloy service.
3. **Verifies** the agent is up by hitting `http://localhost:12345/-/ready`.

**No config management** - you manage your Alloy config separately. This role only installs/upgrades the Alloy binary and ensures the service runs.

---

## 1️⃣ Repository Layout

```
grafana-alloy-monitoring/
├─ ansible/
│  ├─ ansible.cfg                 # Core Ansible settings (portable roles_path)
│  ├─ requirements.yml            # Collections: ansible.windows, community.windows, amazon.aws
│  ├─ inventory/
│  │  ├─ dev/hosts.yml            # AWS SSM inventory (example instances)
│  │  ├─ staging/hosts.yml        # Staging inventory (placeholders - fill in your instances)
│  │  └─ prod/hosts.yml           # Production inventory (placeholders - fill in your instances)
│  ├─ group_vars/
│  │  └─ all.yml                  # Global defaults (version, service state, etc.)
│  ├─ playbooks/
│  │  └─ deploy_alloy.yml         # Main playbook (Linux play + Windows play)
│  └─ roles/
│     └─ alloy_agent/
│        ├─ defaults/main.yml     # Only a few defaults: version, service state
│        ├─ vars/                 # Platform‑specific paths (Debian, RedHat, Amazon, Suse, Windows)
│        ├─ tasks/main.yml        # **All tasks** – install, service, verify
│        ├─ handlers/main.yml     # Restart handler
│        └─ meta/main.yml         # Galaxy metadata
├─ configs/stage/                 # Reference Alloy config sample (not deployed by the role)
├─ packages/                      # Optional: place local .deb/.rpm/.zip packages here for offline testing
├─ Jenkinsfile                    # Declarative pipeline (see below)
└─ README.md                      # This file
```

---

## 2️⃣ Prerequisites

### Control Node (Where Ansible/Jenkins Runs)

| Component | Minimum Version | Recommended | Notes |
|-----------|----------------|-------------|-------|
| **Ansible Core** | 2.16+ | 2.18+ | `ansible.windows >= 3.2.0` requires ansible-core 2.16+ |
| **Python** | 3.10+ | 3.11+ | ansible-core 2.16 requires Python 3.10+ |
| **boto3 / botocore** | Latest | Latest | Required by `amazon.aws.aws_ssm` connection (AWS SSM inventories) |
| **AWS CLI** | v2 | Latest | For the controller's AWS credentials/profile |
| **pip/pip3** | 21.0+ | Latest | For installing `ansible-lint`, collections |
| **ansible-lint** | 6.0+ | Latest | Installed via `pip3 install ansible-lint` |
| **Git** | 2.30+ | Latest | For Jenkins SCM checkout |

### Jenkins Server

| Component | Minimum Version | Recommended | Required Plugins |
|-----------|----------------|-------------|------------------|
| **Jenkins** | 2.375.x LTS | 2.426.x LTS | See below |
| **Java** | 11 / 17 | 17 (JDK 17) | Jenkins 2.375+ requires Java 11+; 17 recommended |

#### Required Jenkins Plugins (8 Essential)

| # | Plugin | Minimum Version | Purpose | Required? |
|---|--------|----------------|---------|-----------|
| 1 | **Pipeline** | 2.5 | Core Pipeline DSL (`pipeline {}`) | ✅ Yes |
| 2 | **Pipeline: Declarative** | 1.9 | Declarative pipeline syntax | ✅ Yes |
| 3 | **Email Extension** | 2.96 | `emailext()` notification in `post` block | ✅ Yes |
| 4 | **Git** | 4.10 | SCM checkout from Git | ✅ Yes |
| 5 | **Timestamper** | 1.12 | `timestamps()` in options | ✅ Yes |
| 6 | **Build Timeout** | 1.20 | `timeout()` in options | ✅ Yes |
| 7 | **Pipeline Utility Steps** | 2.11 | `fileExists()`, `readFile` etc. | ✅ Yes |
| 8 | **Pipeline: Stage View** | 2.19 | Visual pipeline graph in Jenkins UI | ✅ Yes |

#### Optional / Supporting Plugins
| Plugin | Minimum Version | Purpose | Required? |
|--------|----------------|---------|-----------|
| **Build User Vars** | 1.9 | `BUILD_USER_ID` in email notifications | 🔸 Optional |
| **AWS Credentials** | 1.42 | Bind AWS credentials for SSM (or use an IAM role on the agent) | 🔸 Optional |
| **Credentials Binding** | 1.27 | Binding credentials as env vars (optional) | 🔸 Optional |
| **Pipeline: Graph Analysis** | 1.10 | Pipeline graph analysis (used by Stage View) | 🔸 Optional |
| **Disk Usage** | 1.0 | Monitor workspace disk usage | 🔸 Optional |

### Target Hosts (Managed Nodes)

#### Linux Targets
| OS | Version | Kernel | Python | Notes |
|----|---------|--------|--------|-------|
| **Ubuntu** | 20.04 LTS, 22.04 LTS, 24.04 LTS | 5.4+ | 3.10+ (built-in) | `apt` package manager |
| **Debian** | 11 (Bullseye), 12 (Bookworm) | 5.10+ | 3.9+ | `apt` package manager |
| **RHEL / Rocky / AlmaLinux** | 8.x, 9.x | 4.18+ / 5.14+ | 3.6+ / 3.9+ | `dnf`/`yum`; EPEL may be needed |
| **CentOS Stream** | 8, 9 | 4.18+ / 5.14+ | 3.6+ / 3.9+ | |
| **SLES** | 15 SP4+ | 5.14+ | 3.6+ | `zypper` package manager |
| **Amazon Linux** | 2, 2023 | 5.10+ / 6.1+ | 3.7+ / 3.9+ | `dnf`/`yum` |

**Common Linux Requirements:**
- **SSH** access (OpenSSH 7.6+)
- **Python 3** installed (for Ansible modules)
- **sudo/root** access for package install & service management
- **systemd** (all supported versions use systemd)

#### Windows Targets
| OS | Version | Build | PowerShell | Notes |
|----|---------|-------|------------|-------|
| **Windows Server** | 2019, 2022 | 17763+ / 20348+ | 5.1+ (built-in) | WinRM or SSH |
| **Windows 10/11 Pro/Ent** | 1809+ (1809+) | 17763+ | 5.1+ | WinRM or SSH |

**Windows Requirements:**
| Method | Requirements |
|--------|--------------|
| **AWS SSM** (current inventories) | SSM Agent + instance profile, `amazon.aws` collection, `ansible_shell_type: powershell`, S3 transfer bucket |
| **WinRM** | WinRM 3.0+, HTTPS listener (port 5986), `AllowUnencrypted=false`, Basic auth or Kerberos |
| **SSH** | OpenSSH Server (Windows 1809+), SSH key auth, `ansible_connection=ssh`, `ansible_shell_type: powershell` |

**Common Windows Requirements:**
- **PowerShell 5.1+** (built-in on supported versions)
- **.NET Framework 4.7.2+** (for Alloy installer)
- **Administrator** privileges for service install
- **PowerShell ExecutionPolicy** `RemoteSigned` or `Unrestricted`

### Network & Connectivity

| Path | Port | Protocol | Purpose |
|------|------|----------|---------|
| Jenkins → Ansible Controller | 22 | SSH | Jenkins agent connection |
| Ansible Controller → Linux Targets | 22 | SSH | Ansible management |
| Ansible Controller → Windows (WinRM) | 5985/5986 | HTTP/HTTPS | WinRM management |
| Ansible Controller → Windows (SSH) | 22 | SSH | SSH management |
| Target Hosts → Grafana Cloud | 443 | HTTPS | `prometheus.remote_write` (your Alloy config handles this) |

### 🔐 SSH / Inventory Configuration (Remote Host Access)

#### SSH Host Key Checking Configuration

The playbook uses `host_key_checking = False` in `ansible.cfg` for simplicity. For production, you may want to enable host key verification:

**ansible.cfg** (current - permissive):
```ini
[defaults]
host_key_checking = False
```

**ansible.cfg** (production - strict):
```ini
[defaults]
host_key_checking = True
```

**Per-host override** (inventory):
```yaml
# inventory/prod/hosts.yml
all:
  children:
    linux_hosts:
      hosts:
        prod-db-01:
          ansible_host: 10.10.11.11
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          # Host key checking per host (optional)
          ansible_ssh_common_args: '-o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts'
```

#### Inventory Configuration Examples

> **This repo's inventories use AWS SSM** (`ansible_connection: amazon.aws.aws_ssm`). SSH and WinRM examples are kept below for reference.

**AWS SSM (current inventories):**
```yaml
# inventory/dev/hosts.yml
all:
  children:
    linux_hosts:
      hosts:
        ubuntu-linux-dev-01:
          ansible_host: 40.192.24.0
          ansible_connection: amazon.aws.aws_ssm
          ansible_aws_ssm_instance_id: i-078e4fad1d4254259
          ansible_aws_ssm_region: ap-south-2
          ansible_aws_ssm_bucket_name: my-ansible-ssm-transfers-unique-name

    windows_hosts:
      hosts:
        windows-dev-01:
          ansible_host: 18.60.146.195
          ansible_connection: amazon.aws.aws_ssm
          ansible_aws_ssm_instance_id: i-0e3bc3db5e9b49485
          ansible_aws_ssm_region: ap-south-2
          ansible_aws_ssm_bucket_name: my-ansible-ssm-transfers-unique-name
          ansible_shell_type: powershell
```

**AWS SSM requirements:**
| Requirement | Details |
|-------------|---------|
| **Controller packages** | `pip3 install boto3 botocore` (or `python3-boto3`), AWS CLI v2 configured with credentials |
| **Session Manager plugin** | Only needed for manual `aws ssm start-session` troubleshooting. Ansible's `amazon.aws.aws_ssm` plugin talks to the SSM API via boto3, so the plugin binary is **not** required |
| **Ansible collection** | `amazon.aws >= 8.0.0` (installed from `requirements.yml`) |
| **Target host** | SSM Agent running + instance profile/role with `AmazonSSMManagedInstanceCore` |
| **S3 transfer bucket** | `ansible_aws_ssm_bucket_name` must exist in the same region (used for file transfers, e.g. Windows `win_copy`) |
| **Windows shell** | Set `ansible_shell_type: powershell` for Windows targets |
| **IAM (controller)** | `ssm:StartSession`, `ssm:SendCommand`, `ssm:GetCommandInvocation`, `s3:PutObject/GetObject` on the transfer bucket |

> `windows_hosts` in `inventory/dev/hosts.yml` is currently commented out. Uncomment it (and replace the instance ID/region) before running against Windows.

**Linux Hosts (SSH Key Auth):**
```yaml
# inventory/prod/hosts.yml
all:
  children:
    linux_hosts:
      hosts:
        prod-db-01:
          ansible_host: 10.10.11.11
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          ansible_become: true
          ansible_become_method: sudo
```

**Windows Hosts (SSH):**
```yaml
# inventory/prod/hosts.yml
  windows_hosts:
    hosts:
      prod-sql-01:
        ansible_host: 10.10.11.21
        ansible_user: administrator
        ansible_connection: ssh
        ansible_ssh_private_key_file: ~/.ssh/id_rsa
        ansible_shell_type: powershell
```

**Windows Hosts (WinRM - Alternative):**
```yaml
# inventory/prod/hosts.yml
  windows_hosts:
    hosts:
      prod-sql-01:
        ansible_host: 10.10.11.21
        ansible_user: administrator
        ansible_password: "{{ vault_windows_password }}"
        ansible_connection: winrm
        ansible_winrm_transport: ntlm
        ansible_winrm_server_cert_validation: ignore
        ansible_port: 5986
```

#### Jenkins AWS Credentials (for SSM)

The pipeline no longer uses `sshagent`; the AWS SSM connection plugin authenticates with credentials available to the Jenkins agent.

1. **Recommended: IAM role on the Jenkins agent**
   - Attach an IAM role with SSM (`ssm:StartSession`, `ssm:SendCommand`, `ssm:GetCommandInvocation`) and S3 access for the transfer bucket.
   - No Jenkins credential configuration required.

2. **Alternative: AWS Credentials plugin**
   - Add an AWS credential (`Kind: AWS Credentials`) and bind it in the pipeline:
   ```groovy
   withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-ssm-creds']]) {
       sh "ansible-playbook ..."
   }
   ```

3. **Verify from the agent before running the pipeline:**
   ```bash
   aws sts get-caller-identity
   ansible-inventory -i ansible/inventory/dev/hosts.yml --list
   ```

#### SSH Known Hosts Management

**Option 1: Pre-populate known_hosts (Recommended for Production)**
```bash
# On Ansible controller, pre-scan all target hosts
ssh-keyscan -H 10.10.11.11 10.10.11.12 10.10.11.21 >> ~/.ssh/known_hosts
```

**Option 2: Disable Strict Checking (Development Only)**
```yaml
# ansible.cfg
[defaults]
host_key_checking = False
```
Or per-playbook:
```bash
ansible-playbook -i inventory/prod/hosts.yml playbooks/deploy_alloy.yml \
  -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
```

#### Ansible.cfg Reference (Current Settings)
```ini
# ansible/ansible.cfg
[defaults]
inventory = inventory/dev
# Absolute path used for local testing on the cloud controller:
# roles_path = /root/grafana-alloy-monitoring/ansible/roles
# Portable path resolved relative to this file (works on any host/Jenkins agent)
roles_path = roles
host_key_checking = False      # Set to True for production
retry_files_enabled = False
interpreter_python = auto_silent
gathering = smart
stdout_callback = default
forks = 25
timeout = 60

[ssh_connection]
pipelining = True
```

> **Important:** when running from the project root, point Ansible at the config file, otherwise `ansible/ansible.cfg` is not loaded and the role cannot be found:
> ```bash
> ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ...
> ```
> In Jenkins this is set automatically via `ANSIBLE_CONFIG=${WORKSPACE}/ansible/ansible.cfg`.

---

### Software Versions Compatibility Matrix

| Component | Compatible Versions |
|-----------|---------------------|
| **Alloy** | 1.11.x → 1.20.x (tested up to 1.20.2) |
| **Grafana Cloud** | Current (Prometheus remote-write API) |
| **Oracle Instant Client** | 19.x, 21.x (on Alloy host for Oracle exporter) |
| **MSSQL Driver** | Microsoft ODBC Driver 17/18 for SQL Server (on Alloy host) |

### Quick Version Check Commands

```bash
# Control node
ansible --version          # Should show 2.14+
python3 --version          # 3.9+
pip3 --version             # 21.0+
ansible-galaxy collection list | grep -E 'windows|community'
ansible-lint --version     # 6.0+

# Target Linux
ssh user@host "python3 --version && cat /etc/os-release"

# Target Windows
ssh user@host "powershell -Command \"[System.Environment]::OSVersion.Version; \$PSVersionTable.PSVersion\""

# Jenkins
# Check in Jenkins UI: Manage Jenkins → System Information
```

---

## 📦 Installing Ansible Collections (requirements.yml)

The `ansible/requirements.yml` declares the Ansible collections needed for Windows support. Install them before running the playbook:

### Option 1: Manual install (local / CI)
```bash
cd grafana-alloy-monitoring/ansible
ansible-galaxy collection install -r requirements.yml
```
This downloads `ansible.windows` and `community.windows` into `~/.ansible/collections` (or the path set by `COLLECTIONS_PATHS`).

### Option 2: Inside Jenkins pipeline (automatic)
The pipeline's **Deploy Alloy** stage runs on an agent labeled `ansible-controller`. Ensure that agent has the collections pre‑installed, or add a setup stage:

```groovy
stage('Setup Ansible Collections') {
    steps {
        sh '''
            cd ansible
            ansible-galaxy collection install -r requirements.yml
        '''
    }
}
```

> **Tip:** Pin the collection versions in `requirements.yml` (already done) to avoid unexpected upgrades.

---

## 🔍 Ansible Lint & Syntax Validation

The pipeline includes a **dedicated lint & syntax check stage** that runs before deployment:

### What it checks
1. **ansible-lint** – Lints playbooks, roles, and tasks for best practices, deprecations, and potential bugs
2. **ansible-playbook --syntax-check** – Validates YAML syntax and basic Ansible syntax

### Local usage
```bash
# Install ansible-lint (once)
pip3 install ansible-lint

# Run lint on the playbook
cd grafana-alloy-monitoring/ansible
ansible-lint playbooks/deploy_alloy.yml

# Syntax check (dry-run, no changes)
ansible-playbook --syntax-check -i inventory/dev/hosts.yml playbooks/deploy_alloy.yml \
  -e "alloy_version=1.19.2 alloy_download_base_url=https://your-artifactory.example.com/artifactory/grafana-alloy"
```

### In Jenkins Pipeline
The **Ansible Lint & Syntax Check** stage runs automatically before deployment:
1. Installs `ansible-lint` if missing
2. Runs `ansible-lint` on the playbook with the role
3. Runs `ansible-playbook --syntax-check` with the selected environment's inventory and parameters

> **Note:** The pipeline installs `ansible-lint` via `pip3` if not present on the agent. For production, pre-install it on your `ansible-controller` agents.

> **⚠️ Fail-Fast Behavior:** If the **Ansible Lint & Syntax Check** stage fails (lint errors or syntax errors), the pipeline **stops immediately** and does **not** proceed to the Deploy stage. This is intentional – it prevents deploying code with lint/syntax errors.

---

## 3️⃣ Quick Local Test (optional)

```bash
cd /root/grafana-alloy-monitoring
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory/dev/hosts.yml ansible/playbooks/deploy_alloy.yml \
  -e "alloy_version=1.19.2 alloy_download_base_url=https://your-artifactory.example.com/artifactory/grafana-alloy"
```

---

## 4️⃣ Jenkins Pipeline – Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ENVIRONMENT` | Choice | `dev` | Target inventory directory (`dev`, `staging`, `prod`). |
| `ALLOY_VERSION` | String | `1.19.2` | Grafana Alloy release to install (must exist in Artifactory). |
| `ARTIFACTORY_URL` | String | `https://your-artifactory.example.com/artifactory/grafana-alloy` | Base URL for Alloy packages in Artifactory. |
| `HOST_LIMIT` | String | *(empty)* | Ansible `--limit` pattern (e.g. `db_mysql`). |
| `DEPLOY_SERIAL` | String | `50%` | Rolling‑update batch size (Ansible `serial`). |
| `DRY_RUN` | Boolean | `false` | Run `ansible-playbook --check --diff` (no changes). |
| `EXTRA_VARS` | String | *(empty)* | Additional Ansible extra vars (e.g. `alloy_package_local_dir=/tmp/packages`). |
| `EMAIL_RECIPIENTS` | String | *(empty)* | Comma-separated email addresses for notifications. |

---

## 5️⃣ Pipeline Stages

| Stage | When | Action |
|-------|------|--------|
| **Parameter validation** | Always | Ensures `ALLOY_VERSION` is provided. |
| **Setup Ansible Collections** | Always | Installs `ansible.windows`, `community.windows`, `amazon.aws`. |
| **Ansible Lint & Syntax Check** | Always | Runs `ansible-lint` + `ansible-playbook --syntax-check`. Fails fast if issues found. |
| **Deploy Alloy** | Always (`--check --diff` when `DRY_RUN` is true) | Runs `ansible-playbook` with chosen parameters (AWS SSM credentials from the agent environment). |
| **Post-Deploy Verification** | `DRY_RUN == false` | Re-runs the playbook with `--tags verify` (Alloy `/-/ready` check). |
| **Approval (prod only)** | `ENVIRONMENT == 'prod'` | Manual approval gate before production deployment. |

---

## 🧪 Local Testing with Local Packages

You can test the playbook **without downloading from Artifactory** by placing packages locally:

### 1. Create packages directory
```bash
mkdir -p packages/
```

### 2. Place packages in the directory
```
packages/
├── alloy-1.19.2-1.amd64.deb          # Debian/Ubuntu
├── alloy-1.19.2-1.amd64.rpm          # RHEL/Rocky/Alma
└── alloy-installer-windows-amd64.exe.zip  # Windows
```

### 3. Run the playbook from the project root
```bash
cd /root/grafana-alloy-monitoring
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory/dev/hosts.yml ansible/playbooks/deploy_alloy.yml \
  -e "alloy_version=1.19.2 alloy_package_local_dir=/root/grafana-alloy-monitoring/packages alloy_download_base_url=dummy"
```

> **Note:** `alloy_package_local_dir` must be an **absolute path** on the Ansible controller. Relative paths are resolved against the role/playbook directories, not your current directory, so `../packages` will fail.

### 4. Run against a single host
```bash
# Linux host defined in inventory/dev/hosts.yml
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory/dev/hosts.yml ansible/playbooks/deploy_alloy.yml \
  -e "alloy_version=1.19.2 alloy_package_local_dir=/root/grafana-alloy-monitoring/packages alloy_download_base_url=dummy" \
  --limit ubuntu-linux-dev-01
```

For Windows, uncomment `windows_hosts` in `inventory/dev/hosts.yml` first, then use `--limit windows-dev-01`.

### How it works
- If `alloy_package_local_dir` is set and packages exist locally → **uses local packages** (no download)
- If `alloy_package_local_dir` is empty or packages missing → **downloads from Artifactory**

---

## 6️⃣ How to Create the Pipeline in Jenkins

1. **Install required plugins** (Manage Jenkins → Plugins → Available):
   - **Pipeline** (built‑in)
   - **Email Extension** (for `emailext` notifications)
   - **Git** (if pulling from a Git repo)

2. **Configure AWS access for the agent**:
   - Attach an IAM role with SSM + S3 permissions to the Jenkins agent (recommended), **or** add an AWS credential and bind it with `withCredentials`.

3. **Create a new Pipeline job**:
   - **New Item** → name it (e.g. `Deploy-Alloy-Agent`) → **Pipeline** → OK.
   - **Pipeline section**:
     - **Definition**: *Pipeline script from SCM*
     - **SCM**: Git → Repository URL → your repo (e.g. `https://github.com/your-org/grafana-alloy-monitoring.git`)
     - **Script Path**: `Jenkinsfile` (default)
   - **Save**.

4. **Run the pipeline**:
   - Click **Build with Parameters**.
   - Fill in the parameters (see table above). **`ALLOY_VERSION` and `ARTIFACTORY_URL` are required.**
   - Click **Build**.
   - Watch the console output – you'll see the Ansible run, and for prod an approval prompt will appear.

---

## 7️⃣ Sample Config File (Manage Separately)

**File:** `configs/stage/alloy-windows-vm-oracle-mssql.alloy`

This ready‑to‑use sample collects:
- **Windows VM metrics** via `prometheus.exporter.windows`
- **Oracle Database** metrics via `prometheus.exporter.oracledb`
- **Microsoft SQL Server** metrics via `prometheus.exporter.mssql`
- **Alloy self‑monitoring**
- Sends everything to **Grafana Cloud (Mimir)** via `prometheus.remote_write`

> **Note:** This config file is for reference only. The deployment playbook does NOT manage configs. You manage your Alloy config separately and apply it via your own process.

### Prerequisites for this config
| Component | Requirement |
|-----------|-------------|
| Windows VM | Windows Exporter runs on the same Windows host |
| Oracle DB | Oracle Instant Client installed on the Alloy host; network access to Oracle DB |
| MSSQL | Network access to SQL Server; SQL authentication user with monitoring permissions |
| Grafana Cloud | Valid Grafana Cloud account with Prometheus remote-write endpoint |

---

## 8️⃣ Troubleshooting Cheat‑Sheet

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `Alloy did not become ready` | Service didn’t start or config error | Check `journalctl -u alloy` (Linux) or Event Viewer → **Applications and Services Logs → Grafana Alloy** (Windows). |
| `Unsupported OS` | Host OS not Debian/RedHat/Windows | Add the OS family to the assert or extend the role. |
| Permission denied | SSH user lacks sudo/root rights | Ensure the SSH user has sudo/root rights (Linux) or Administrator (Windows). |
| Oracle exporter fails | Oracle Instant Client not installed or wrong connection string | Install Oracle Instant Client; verify connection string format `oracle://user:pass@host:port/service` |
| MSSQL exporter fails | Wrong connection string or network blocked | Verify SQL Server allows remote connections; check firewall; use `sqlserver://user:pass@host:port?encrypt=disable` |

---

## 🔟 Summary

1. **Configure Artifactory URL** in `ansible/group_vars/all.yml` or Jenkins parameter.
2. **Push** to Git.
3. **Run the Jenkins pipeline** with `ALLOY_VERSION` and `ARTIFACTORY_URL`.
3. **Alloy is installed, service started, health‑checked** – done.

No config management, no hidden templates – just **Alloy installed and running**. 🚀