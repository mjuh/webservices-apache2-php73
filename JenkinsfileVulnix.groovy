@Library('mj-shared-library') _

pipeline {
    agent { label "nixbld" }
    parameters {
        string(name: 'DOCKER_IMAGE', description: 'Input Docker image derivation')
    }
    environment {
        JUNIT_OUTPUT_DIRECTORY = "result/${env.JOB_NAME}"
        JUNIT_OUTPUT_PATH = "$JUNIT_OUTPUT_DIRECTORY/junit-vulnix-${env.BUILD_NUMBER}"
        JUNIT_OUTPUT_XML = "${JUNIT_OUTPUT_PATH}.xml"
        JUNIT_OUTPUT_JSON = "${JUNIT_OUTPUT_PATH}.json"
        VULNIX_CACHE_DIRECTORY = "$JUNIT_OUTPUT_DIRECTORY/.cache/vulnix"
    }
    stages {
        stage("Build junit") {
            steps {
                script {
                    sh "mkdir -p $JUNIT_OUTPUT_DIRECTORY $VULNIX_CACHE_DIRECTORY"
                    writeFile (file: JUNIT_OUTPUT_JSON,
                               text: (sh (script: "vulnix --cache-dir $VULNIX_CACHE_DIRECTORY --json $params.DOCKER_IMAGE || true",
                                          returnStdout: true)).trim())
                    sh "scripts/vulnix2junit.py"
                    junit JUNIT_OUTPUT_XML
                }
            }
        }
    }
    post {
        always { sh "rm --force --recursive $JUNIT_OUTPUT_DIRECTORY $VULNIX_CACHE_DIRECTORY" }
        success { notifySlack "Build ${JOB_NAME} succeeded" , "green" }
        failure { notifySlack "Build failled: ${JOB_NAME} [<${RUN_DISPLAY_URL}|${BUILD_NUMBER}>]", "red" }
    }
}
