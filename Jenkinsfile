@Library('mj-shared-library') _
def dockerImage = null

pipeline {
        agent { label 'master' }
        environment {
            PROJECT_NAME = gitRemoteOrigin.getProject()
            GROUP_NAME = gitRemoteOrigin.getGroup()
        }
        options {
            gitLabConnection(Constants.gitLabConnection)
            gitlabBuilds(builds: ['Build', 'Push Docker image'])
            buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '10'))
        }
        stages {
            stage('Build') {
                steps {
                    gitlabCommitStatus(STAGE_NAME) {
                        script { dockerImage = nixBuildDocker namespace: GROUP_NAME, name: PROJECT_NAME, tag: BRANCH_NAME }
                    }
                }
            }
            stage('Push Docker image') {
                steps {
                    gitlabCommitStatus(STAGE_NAME) {
                        pushDocker image: dockerImage
                    }
                }
            }
        }
        post {
            success { cleanWs() }
            failure { notifySlack "Build failled: ${JOB_NAME} [<${RUN_DISPLAY_URL}|${BUILD_NUMBER}>]", "red" }
        }
    }
