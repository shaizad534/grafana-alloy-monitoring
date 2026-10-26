// Captured by the Post-Deploy Verification stage and embedded in the email.
// One playbook runs in every mode: ansible/playbooks/deploy_alloy.yml.
// The PLAYBOOK parameter only changes the inventory and the deploy_onprem
// gate: onprem = ansible/inventory/onprem/hosts.ini with deploy_onprem=true,
// role = ansible/inventory/<ENVIRONMENT>/hosts.ini with deploy_onprem=false.
// Using a variable instead of currentBuild.rawBuild avoids the Jenkins script
// approval / sandbox restriction on rawBuild.
def verifyOutput = ''

// Quote a value for safe interpolation into a POSIX shell command line. The
// values come from build parameters, so a single quote or a space must not be
// able to break the ansible-playbook command.
def shQuote(String value) {
    return "'" + (value ?: '').replace("'", "'\\''") + "'"
}

// Escape a value before it is embedded in the HTML notification body.
def htmlEscape(value) {
    return (value ?: '').toString()
        .replace('&', '&amp;')
        .replace('<', '&lt;')
        .replace('>', '&gt;')
}

pipeline {
    agent { label 'ansible-controller' }

    options {
        timestamps()
        // The prod approval below can wait up to 24 hours, so the pipeline
        // timeout must be larger than that. The work stages carry their own,
        // tighter timeouts.
        timeout(time: 26, unit: 'HOURS')
        disableConcurrentBuilds(abortPrevious: false)
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        choice(name: 'PLAYBOOK', choices: ['role', 'onprem'], description: 'Target mode for ansible/playbooks/deploy_alloy.yml: role = Linux/Windows roles with ansible/inventory/<ENVIRONMENT>/hosts.ini; onprem = imported on-prem play with ansible/inventory/onprem/hosts.ini and deploy_onprem=true')
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'], description: 'Role deploy only: target inventory directory. On-prem always uses ansible/inventory/onprem/hosts.ini and always requires approval, so ENVIRONMENT does not change the on-prem target.')
        string(name: 'ALLOY_VERSION', defaultValue: '1.19.2', description: 'Grafana Alloy version to deploy (applies to both playbooks; the on-prem playbook needs the matching package in packages/).')
        string(name: 'ARTIFACTORY_URL', defaultValue: 'https://github.com/grafana/alloy/releases/download', description: 'Role deploy only: base URL for Alloy packages (GitHub by default; override for an internal Artifactory mirror)')
        string(name: 'HOST_LIMIT', defaultValue: '', description: 'Ansible --limit pattern (e.g. "linux_hosts", "linux_servers" or a host name). Applies to both playbooks.')
        string(name: 'DEPLOY_SERIAL', defaultValue: '50%', description: 'Role deploy only: rolling deploy serial percent')
        booleanParam(name: 'DRY_RUN', defaultValue: false, description: 'Run in check mode (no changes). Not supported for the on-prem playbook.')
        string(name: 'EXPORTER_NAME', defaultValue: '', description: 'Optional: exporter artifact name (e.g. jmx-exporter). When set, install_exporter=true is passed to both playbooks.')
        string(name: 'EXPORTER_VERSION', defaultValue: '', description: 'Optional: exporter artifact version (e.g. 1.5.0). Required when EXPORTER_NAME is set.')
        string(name: 'EXPORTER_REPO_URL', defaultValue: '', description: 'Optional: exporter repository root URL. Required when EXPORTER_NAME is set (the role default is a placeholder).')
        password(name: 'REPO_TOKEN', defaultValue: '', description: 'Optional: exporter repository token (masked). Passed as repo_token to both playbooks.')
        string(name: 'EXTRA_VARS', defaultValue: '', description: 'Additional ansible extra vars (e.g. "alloy_package_local_dir=/tmp/packages install_exporter=false"). Applied last, so it wins.')
        string(name: 'EMAIL_RECIPIENTS', defaultValue: '', description: 'Comma-separated email addresses for notifications')
    }

    environment {
        ANSIBLE_CONFIG = "${WORKSPACE}/ansible/ansible.cfg"
        ANSIBLE_HOST_KEY_CHECKING = 'False'
    }

    stages {

        stage('Parameter Validation') {
            steps {
                script {
                    if (!params.ALLOY_VERSION?.trim()) {
                        error "ALLOY_VERSION must be set"
                    }
                    if (params.EXPORTER_NAME?.trim() && !params.EXPORTER_VERSION?.trim()) {
                        error "EXPORTER_VERSION must be set when EXPORTER_NAME is set"
                    }
                    if (params.EXPORTER_NAME?.trim() && !params.EXPORTER_REPO_URL?.trim()) {
                        error "EXPORTER_REPO_URL must be set when EXPORTER_NAME is set (the role default is a placeholder URL)"
                    }
                    if (params.PLAYBOOK == 'onprem' && params.DRY_RUN) {
                        // The on-prem playbook has no check-mode support
                        // (several tasks depend on command results), so fail
                        // early instead of a confusing run.
                        error "DRY_RUN is not supported for the on-prem play (deploy_onprem=true). Set DRY_RUN=false."
                    }
                }
            }
        }

        stage('Setup Ansible Collections') {
            steps {
                script {
                    // Install required Ansible collections on control node (Jenkins agent)
                    sh '''
                        cd ansible
                        echo "=== Installing Ansible collections ==="
                        ansible-galaxy collection install -r requirements.yml
                    '''
                }
            }
        }

        stage('Ansible Lint & Syntax Check') {
            options {
                timeout(time: 30, unit: 'MINUTES')
            }
            steps {
                script {
                    // Install ansible-lint if missing
                    sh '''
                        if ! command -v ansible-lint &> /dev/null; then
                            echo "Installing ansible-lint..."
                            pip3 install --quiet ansible-lint
                        fi
                    '''
                    // Both modes run the same playbook. Only the inventory and
                    // the deploy_onprem gate differ.
                    def isOnprem = params.PLAYBOOK == 'onprem'
                    def inventoryPath = isOnprem
                        ? 'inventory/onprem/hosts.ini'
                        : "inventory/${params.ENVIRONMENT}/hosts.ini"
                    def gate = isOnprem ? 'true' : 'false'
                    sh """
                        cd ansible
                        echo "=== Running ansible-lint ==="
                        ansible-lint playbooks/deploy_alloy.yml
                        echo "=== Running ansible-playbook syntax check ==="
                        ansible-playbook --syntax-check -i ${inventoryPath} playbooks/deploy_alloy.yml \\
                            -e "alloy_version=${params.ALLOY_VERSION} alloy_download_base_url=${params.ARTIFACTORY_URL} deploy_serial=${params.DEPLOY_SERIAL} deploy_onprem=${gate}"
                    """
                }
            }
        }

        stage('Approval (prod / on-prem)') {
            when {
                expression {
                    // On-prem has a single inventory and is treated as
                    // production, so it always needs approval. Role mode is
                    // gated by ENVIRONMENT.
                    params.PLAYBOOK == 'onprem' || params.ENVIRONMENT == 'prod'
                }
            }
            steps {
                script {
                    // Must run BEFORE the deploy stage: this gate authorises the
                    // production change, it does not confirm it after the fact.
                    def target = params.PLAYBOOK == 'onprem' ? 'ON-PREM (linux_servers)' : 'PROD'
                    def version = params.PLAYBOOK == 'onprem' ? 'the on-prem playbook version' : "Alloy ${params.ALLOY_VERSION}"
                    timeout(time: 24, unit: 'HOURS') {
                        input message: "Approve deployment of ${version} to ${target}?", ok: 'Deploy', submitter: 'ops-admins,release-managers'
                    }
                }
            }
        }

        stage('Deploy Alloy') {
            options {
                timeout(time: 2, unit: 'HOURS')
            }
            steps {
                script {
                    // One playbook for every mode. PLAYBOOK selects the
                    // inventory and sets deploy_onprem, which gates the
                    // imported on-prem play inside deploy_alloy.yml.
                    def isOnprem = params.PLAYBOOK == 'onprem'
                    def inventoryPath = isOnprem
                        ? 'ansible/inventory/onprem/hosts.ini'
                        : "ansible/inventory/${params.ENVIRONMENT}/hosts.ini"
                    def playbookPath = 'ansible/playbooks/deploy_alloy.yml'

                    // No sshagent wrapper needed: the inventories use the AWS SSM
                    // connection plugin, which authenticates with the agent's AWS credentials.
                    //
                    // Each entry is [value: '<key>=<value>', secret: <bool>]. The
                    // real command and the echoed command are built from the same
                    // list, so a secret can never leak through the display copy.
                    def extra = []
                    // The gate: the on-prem play inside deploy_alloy.yml only
                    // runs when this is true.
                    extra << [value: "deploy_onprem=${isOnprem}"]
                    // The Alloy version applies to both playbooks. The on-prem
                    // play loads defaults/main.yml (1.19.2), so this -e
                    // overrides it; the matching package must exist in packages/.
                    extra << [value: "alloy_version=${params.ALLOY_VERSION}"]
                    if (!isOnprem) {
                        // Role-only package source and rolling deploy settings.
                        extra << [value: "alloy_download_base_url=${params.ARTIFACTORY_URL}"]
                        extra << [value: "deploy_serial=${params.DEPLOY_SERIAL}"]
                    } else {
                        // Pin the on-prem source directories to the workspace
                        // root. EXTRA_VARS is appended last, so it can override.
                        extra << [value: "alloy_pkg_dir=${WORKSPACE}/packages"]
                        extra << [value: "alloy_support_files_dir=${WORKSPACE}/configs"]
                    }
                    // Exporter settings use the same role variable names for
                    // both playbooks. EXTRA_VARS still wins if it repeats them.
                    if (params.EXPORTER_NAME?.trim()) {
                        extra << [value: 'install_exporter=true']
                        extra << [value: "exporter_name=${params.EXPORTER_NAME.trim()}"]
                        extra << [value: "exporter_version=${params.EXPORTER_VERSION.trim()}"]
                        extra << [value: "exporter_repo_root_url=${params.EXPORTER_REPO_URL.trim()}"]
                    }
                    if (params.REPO_TOKEN?.trim()) extra << [value: "repo_token=${params.REPO_TOKEN}", secret: true]
                    if (params.EXTRA_VARS?.trim()) extra << [value: params.EXTRA_VARS, secret: true]

                    def limitArg = params.HOST_LIMIT?.trim()
                        ? " --limit ${shQuote(params.HOST_LIMIT.trim())}"
                        : ''
                    def dryRunArg = params.DRY_RUN ? ' --check --diff' : ''
                    def base = "ansible-playbook -i ${shQuote(inventoryPath)} ${shQuote(playbookPath)}"

                    def cmd = base + ' ' + extra.collect { "-e " + shQuote(it.value) }.join(' ') + limitArg + dryRunArg
                    // REPO_TOKEN and EXTRA_VARS may contain secrets; mask them
                    // in the echoed command.
                    def displayCmd = base + ' ' + extra.collect {
                        it.secret ? "-e '<redacted>'" : "-e " + shQuote(it.value)
                    }.join(' ') + limitArg + dryRunArg

                    echo "Running: ${displayCmd}"
                    // Disable shell xtrace so secrets passed through EXTRA_VARS
                    // are not echoed by `sh -x` (Ansible output is unaffected).
                    sh(script: "set +x\n${cmd}")
                    // The on-prem play performs its own verification (service
                    // ActiveState, HTTP endpoint, final per-host report), so
                    // the separate Post-Deploy Verification stage is skipped
                    // when PLAYBOOK=onprem.
                }
            }
        }

        stage('Post-Deploy Verification') {
            options {
                timeout(time: 30, unit: 'MINUTES')
            }
            when {
                expression {
                    // The on-prem play (deploy_onprem=true) verifies the
                    // service and endpoint inside the deploy stage, so only
                    // the role mode needs the separate --tags verify run.
                    params.DRY_RUN == false && params.PLAYBOOK == 'role'
                }
            }
            steps {
                script {
                    // Verify the same host subset that was deployed. Without
                    // --limit, a targeted deploy would verify every host in the
                    // inventory (and fail on hosts that were intentionally
                    // skipped).
                    def extra = [
                        [value: "alloy_version=${params.ALLOY_VERSION}"],
                        [value: "alloy_download_base_url=${params.ARTIFACTORY_URL}"]
                    ]
                    if (params.EXTRA_VARS?.trim()) extra << [value: params.EXTRA_VARS, secret: true]

                    def limitArg = params.HOST_LIMIT?.trim()
                        ? " --limit ${shQuote(params.HOST_LIMIT.trim())}"
                        : ''
                    def base = "ansible-playbook -i ${shQuote('ansible/inventory/' + params.ENVIRONMENT + '/hosts.ini')} ${shQuote('ansible/playbooks/deploy_alloy.yml')} --tags verify"

                    def cmd = base + ' ' + extra.collect { "-e " + shQuote(it.value) }.join(' ') + limitArg
                    def displayCmd = base + ' ' + extra.collect {
                        it.secret ? "-e '<redacted>'" : "-e " + shQuote(it.value)
                    }.join(' ') + limitArg
                    echo "Running: ${displayCmd}"

                    // Capture the short verification recap for the email. This
                    // avoids currentBuild.rawBuild, which requires script approval.
                    // `set +x` keeps EXTRA_VARS secrets out of the shell trace.
                    verifyOutput = sh(script: "set +x\n${cmd}", returnStdout: true).trim()
                    echo verifyOutput
                }
            }
        }

    }

    post {
        always {
            // Always send an email with the build status and verification recap
            script {
                def isOnprem = params.PLAYBOOK == 'onprem'
                def targetLabel = isOnprem ? 'on-prem (linux_servers)' : params.ENVIRONMENT
                def versionLabel = isOnprem
                    ? "${params.ALLOY_VERSION} (EXTRA_VARS can override)"
                    : params.ALLOY_VERSION
                def subject = "${currentBuild.currentResult}: Alloy deployment (${isOnprem ? 'on-prem playbook' : 'role'}) to ${targetLabel}"

                // Verification recap instead of currentBuild.rawBuild.getLog(),
                // which requires script approval and is blocked by the sandbox.
                def verifyExcerpt = verifyOutput
                    ? verifyOutput.takeRight(6000)
                    : (isOnprem
                        ? 'On-prem verification runs inside the deploy stage. See the console output for the per-host report.'
                        : 'Verification did not run (deploy failed, DRY_RUN was enabled, or the stage was skipped).')
                verifyExcerpt = htmlEscape(verifyExcerpt)

                def summaryBlock = isOnprem ? '''
                    <p>The on-prem play (deploy_onprem=true) prints a final per-host report in the deploy stage. Look for:</p>
                    <ul>
                        <li><strong>Final deployment status report</strong> - target/installed version, service state, HTTP endpoint, exporter</li>
                        <li><strong>Wait for Alloy service to become active</strong></li>
                    </ul>
                ''' : '''
                    <p>Check the console output above for Alloy deployment status. Look for lines containing:</p>
                    <ul>
                        <li><strong>ALLOY_VERSION=</strong> - Deployed version</li>
                        <li><strong>ALLOY_STATUS=RUNNING</strong> - Agent is running</li>
                        <li><strong>Alloy X.X.X deployed on</strong> - Successful deployment per host</li>
                    </ul>
                '''

                def body = """
                    <h2>Alloy Deployment ${currentBuild.currentResult}</h2>
                    <p><strong>Playbook:</strong> ansible/playbooks/deploy_alloy.yml${isOnprem ? ' (deploy_onprem=true)' : ' (role)'}</p>
                    <p><strong>Target:</strong> ${htmlEscape(targetLabel)}</p>
                    <p><strong>Version:</strong> ${htmlEscape(versionLabel)}</p>
                    <p><strong>Artifactory URL:</strong> ${isOnprem ? 'not used by the on-prem playbook' : htmlEscape(params.ARTIFACTORY_URL)}</p>
                    <p><strong>Build URL:</strong> ${BUILD_URL}</p>
                    <p><strong>Build Number:</strong> ${BUILD_NUMBER}</p>
                    <p><strong>Triggered by:</strong> ${env.BUILD_USER_ID ?: 'unknown'}</p>
                    
                    <h3>Verification Output (tail):</h3>
                    <pre style="background: #f5f5f5; padding: 10px; overflow: auto;">${verifyExcerpt}</pre>
                    <p><a href="${BUILD_URL}console">Open the full console output</a></p>
                    
                    <h3>Deployment Summary:</h3>
                    ${summaryBlock}
                """
                
                if (params.EMAIL_RECIPIENTS?.trim()) {
                    emailext(
                        subject: subject,
                        body: body,
                        to: params.EMAIL_RECIPIENTS,
                        mimeType: 'text/html'
                    )
                } else {
                    echo "No email recipients configured - skipping email notification"
                }
            }
        }
        success { echo "✅ Deploy to ${params.PLAYBOOK == 'onprem' ? 'on-prem (linux_servers)' : params.ENVIRONMENT} finished successfully." }
        failure { echo "❌ Deploy failed – check console output for details." }
    }
}