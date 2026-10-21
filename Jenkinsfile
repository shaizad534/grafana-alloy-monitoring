pipeline {
    agent { label 'ansible-controller' }

    options {
        timestamps()
        timeout(time: 2, unit: 'HOURS')
        disableConcurrentBuilds(abortPrevious: false)
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters(
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'], description: 'Target environment'),
        string(name: 'ALLOY_VERSION', defaultValue: '1.19.2', description: 'Grafana Alloy version to deploy (e.g., 1.19.2, 1.17.1, 1.11.0)'),
        string(name: 'ARTIFACTORY_URL', defaultValue: 'https://your-artifactory.example.com/artifactory/grafana-alloy', description: 'Artifactory base URL for Alloy packages'),
        string(name: 'HOST_LIMIT', defaultValue: '', description: 'Ansible --limit pattern (e.g. "db_mysql")'),
        string(name: 'DEPLOY_SERIAL', defaultValue: '50%', description: 'Rolling deploy serial percent'),
        booleanParam(name: 'DRY_RUN', defaultValue: false, description: 'Run in check mode (no changes)'),
        string(name: 'EMAIL_RECIPIENTS', defaultValue: '', description: 'Comma-separated email addresses for notifications'),
    )

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
                }
            }
        }

        stage('Ansible Lint & Syntax Check') {
            steps {
                script {
                    // Install ansible-lint if missing
                    sh '''
                        if ! command -v ansible-lint &> /dev/null; then
                            echo "Installing ansible-lint..."
                            pip3 install --quiet ansible-lint
                        fi
                    '''
                }
                // Run ansible-lint and syntax check
                sh '''
                    cd ansible
                    echo "=== Running ansible-lint ==="
                    ansible-lint playbooks/deploy_alloy.yml -r roles/
                    echo "=== Running ansible-playbook syntax check ==="
                    ansible-playbook --syntax-check -i inventory/${ENVIRONMENT}/hosts.yml playbooks/deploy_alloy.yml \
                        -e "alloy_version=${ALLOY_VERSION} alloy_download_base_url=${ARTIFACTORY_URL} deploy_serial=${DEPLOY_SERIAL}"
                '''
            }
        }

        stage('Deploy Alloy') {
            when { expression { params.DRY_RUN == false } }
            steps {
                sshagent(['ansible-ssh-key']) {
                    script {
                        def limit = params.HOST_LIMIT?.trim() ? "--limit '${params.HOST_LIMIT}'" : ''
                        def extra = [
                            "-e alloy_version=${params.ALLOY_VERSION}",
                            "-e alloy_download_base_url=${params.ARTIFACTORY_URL}",
                            "-e deploy_serial=${params.DEPLOY_SERIAL}"
                        ]
                        if (params.EXTRA_VARS?.trim()) extra << "-e ${params.EXTRA_VARS}"

                        def cmd = "ansible-playbook -i ansible/inventory/${params.ENVIRONMENT}/hosts.yml ansible/playbooks/deploy_alloy.yml "
                        cmd += extra.join(' ')
                        if (params.HOST_LIMIT?.trim()) cmd += " ${limit}"
                        if (params.DRY_RUN) cmd += " --check --diff"

                        echo "Running: $cmd"
                        sh cmd
                    }
                }
            }
        }

        stage('Post-Deploy Verification') {
            when {
                expression {
                    params.DRY_RUN == false
                }
            }
            steps {
                script {
                    // Run verification playbook to confirm Alloy is running
                    sh "ansible-playbook -i ansible/inventory/${params.ENVIRONMENT}/hosts.yml ansible/playbooks/deploy_alloy.yml --tags verify -e \"alloy_version=${params.ALLOY_VERSION} alloy_download_base_url=${params.ARTIFACTORY_URL}\""
                }
            }
        }

        stage('Approval (prod only)') {
            when {
                expression { params.ENVIRONMENT == 'prod' }
            }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    input message: "Deploy Alloy ${params.ALLOY_VERSION} to PROD?", ok: 'Deploy', submitter: 'ops-admins,release-managers'
                }
            }
        }

    }

    post {
        always {
            // Always send email notification with build status and console output
            script {
                def subject = "${currentBuild.currentResult}: Alloy ${params.ALLOY_VERSION} deployment to ${params.ENVIRONMENT}"
                def body = """
                    <h2>Alloy Deployment ${currentBuild.currentResult}</h2>
                    <p><strong>Environment:</strong> ${params.ENVIRONMENT}</p>
                    <p><strong>Alloy Version:</strong> ${params.ALLOY_VERSION}</p>
                    <p><strong>Artifactory URL:</strong> ${params.ARTIFACTORY_URL}</p>
                    <p><strong>Build URL:</strong> ${BUILD_URL}</p>
                    <p><strong>Build Number:</strong> ${BUILD_NUMBER}</p>
                    <p><strong>Triggered by:</strong> ${BUILD_USER_ID}</p>
                    
                    <h3>Console Output (Last 100 lines):</h3>
                    <pre style="background: #f5f5f5; padding: 10px; overflow: auto;">
                    ${currentBuild.rawBuild.getLog(100).join("\\n")}
                    </pre>
                    
                    <h3>Deployment Summary:</h3>
                    <p>Check the console output above for Alloy deployment status. Look for lines containing:</p>
                    <ul>
                        <li><strong>ALLOY_VERSION=</strong> - Deployed version</li>
                        <li><strong>ALLOY_STATUS=RUNNING</strong> - Agent is running</li>
                        <li><strong>Alloy X.X.X deployed on</strong> - Successful deployment per host</li>
                    </ul>
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
        success { echo "✅ Deploy to ${params.ENVIRONMENT} finished successfully." }
        failure { echo "❌ Deploy failed – check console output for details." }
    }
}