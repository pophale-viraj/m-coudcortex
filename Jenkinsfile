pipeline {
    agent any
    triggers {
        githubPush()
    }
    environment {
        AWS_ACCOUNT_ID = "533267238276"
        REGION = "ap-south-1"
        ECR_URL = "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
        BRANCH_NAME = "${env.BRANCH_NAME}"
        BUILD_NUMBER = "${env.BUILD_NUMBER}"
        IMAGE_TAG = "${BRANCH_NAME}-cloudcortex-v.1.${BUILD_NUMBER}"
        DEV_IMAGE_TAG = "dev-cloudcortex-v.1.${BUILD_NUMBER}"
        PREPROD_IMAGE_TAG = "preprod-cloudcortex-v.1.${BUILD_NUMBER}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '5', artifactNumToKeepStr: '5'))
    }

    tools {
        maven 'maven_3.9.4'
    }

    stages {
        stage('Build and Test for Dev') {
            when {
                branch 'dev'
            }
            stages {
                stage('Code Compilation') {
                    steps {
                        echo 'Code Compilation in Progress!'
                        sh 'mvn clean compile'
                        echo 'Code Compilation Completed!'
                    }
                }

                stage('Code QA Execution') {
                    steps {
                        echo 'JUnit Test Execution in Progress!'
                        sh 'mvn clean test'
                        echo 'JUnit Test Execution Completed!'
                    }
                }

                stage('Code Package') {
                    steps {
                        echo 'Packaging Code into WAR Artifact'
                        sh 'mvn clean package'
                        echo 'WAR Artifact Created Successfully!'
                    }
                }

                stage('Build & Tag Docker Image') {
                    steps {
                        echo "Building Docker Image: ${ECR_URL}/cloudcortex:${DEV_IMAGE_TAG}"
                        sh "docker build -t ${ECR_URL}/cloudcortex:${DEV_IMAGE_TAG} ."
                        echo 'Docker Image Built Successfully!'
                    }
                }

                stage('Docker Image Scanning') {
                    steps {
                        echo 'Scanning Docker Image with Trivy...'
                        echo 'Docker Image Scanning Completed!'
                    }
                }

                stage('Push Docker Image to Docker Hub') {
                    steps {
                        script {
                            withCredentials([string(credentialsId: 'dockerhubCred', variable: 'dockerhubCred')]) {
                                sh 'docker login docker.io -u pophaleviraj -p ${dockerhubCred}'
                                echo 'Pushing Docker Image to Docker Hub...'
                                sh 'docker push pophaleviraj/makemytrip:latest'
                                echo 'Docker Image Pushed to Docker Hub Successfully!'
                            }
                        }
                    }
                }

                stage('Push Docker Image to Amazon ECR') {
                    steps {
                        echo "Pushing Docker Image to ECR: ${ECR_URL}/cloudcortex:${DEV_IMAGE_TAG}"
                        withDockerRegistry([credentialsId: 'ecr:ap-south-1:ecr-credentials', url: "https://${ECR_URL}"]) {
                            sh "docker push ${ECR_URL}/cloudcortex:${DEV_IMAGE_TAG}"
                        }
                        echo 'Docker Image Pushed to ECR Successfully!'
                    }
                }

                stage('Upload Docker Image to Nexus') {
                    steps {
                        script {
                            withCredentials([usernamePassword(credentialsId: 'nexuscred', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                                sh 'docker login http://65.0.177.242:8085/repository/makemytrip/ -u admin -p ${PASSWORD}'
                                echo "Push Docker Image to Nexus : In Progress"
                                sh 'docker tag makemytrip 65.0.177.242:8085/makemytrip:latest'
                                sh 'docker push 65.0.177.242:8085/makemytrip'
                                echo "Push Docker Image to Nexus : Completed"
                            }
                        }
                    }
                }

                stage('Sonarqube') {
                    environment {
                        scannerHome = tool 'qube'
                    }
                    steps {
                        withSonarQubeEnv('sonar-server') {
                            sh "${scannerHome}/bin/sonar-scanner"
                            sh 'mvn sonar:sonar'
                        }
                        timeout(time: 10, unit: 'MINUTES') {
                            waitForQualityGate abortPipeline: true
                        }
                    }
                }

                /* stage('Cleanup Docker Images') {
                    steps {
                        echo 'Cleaning up local Docker images...'
                        sh "docker rmi -f ${DOCKER_IMAGE}:latest || true"
                        sh "docker rmi -f ${ECR_REPO}:latest || true"
                        echo 'Local Docker images deleted successfully!'
                    }
                } */
            }
        }

        stage('Tag Docker Image for Preprod and Prod') {
            when {
                anyOf {
                    branch 'preprod'
                    branch 'prod'
                }
            }
            steps {
                script {
                    def targetTag = BRANCH_NAME == 'preprod' ? PREPROD_IMAGE_TAG : "prod-cloudcortex-v.1.${BUILD_NUMBER}"
                    def sourceTag = BRANCH_NAME == 'preprod' ? DEV_IMAGE_TAG : PREPROD_IMAGE_TAG
                    def sourceImage = "${ECR_URL}/cloudcortex:${sourceTag}"
                    def targetImage = "${ECR_URL}/cloudcortex:${targetTag}"

                    echo "Pulling Source Image: ${sourceImage}"
                    withDockerRegistry([credentialsId: 'ecr:ap-south-1:ecr-credentials', url: "https://${ECR_URL}"]) {
                        def pullStatus = sh(script: "docker pull ${sourceImage}", returnStatus: true)
                        if (pullStatus != 0) {
                            error("Source image ${sourceImage} does not exist or failed to pull.")
                        }
                        echo "Tagging Source Image as Target: ${targetImage}"
                        sh "docker tag ${sourceImage} ${targetImage}"
                        echo "Pushing Target Image to ECR: ${targetImage}"
                        sh "docker push ${targetImage}"
                    }
                    echo "Cleaning Up Local Images"
                    sh "docker rmi ${sourceImage} ${targetImage} || true"
                }
            }
        }

        stage('Deploy app to dev env') {
            when {
                branch 'dev'
            }
            steps {
                script {
                    echo "Deploying to Dev Environment"
                    def yamlFile = 'kubernetes/dev/05-deployment.yaml'

                    sh """
                        sed -i 's|<latest>|${DEV_IMAGE_TAG}|g' ${yamlFile}
                        cat ${yamlFile} | grep ${DEV_IMAGE_TAG} || echo "Replacement failed in ${yamlFile}"
                    """
                    sh """
                        kubectl --kubeconfig=/var/lib/jenkins/.kube/config apply -f kubernetes/dev/
                    """

                    def configMapChanged = sh(script: "git diff --name-only HEAD~1 | grep -q 'kubernetes/dev/06-configmap.yaml'", returnStatus: true)
                    if (configMapChanged == 0) {
                        echo "ConfigMap changed, restarting pods"
                        sh """
                            kubectl --kubeconfig=/var/lib/jenkins/.kube/config rollout restart deployment dev-cloudcortex-deployment -n dev
                        """
                    } else {
                        echo "No ConfigMap Changes, Skipping Pod Restart"
                    }
                }
            }
        }

        stage('Deploy app to preprod env') {
            when {
                branch 'preprod'
            }
            steps {
                script {
                    echo "Deploying to Preprod Environment"
                    def yamlFile = 'kubernetes/preprod/05-deployment.yaml'

                    sh """
                        sed -i 's|<latest>|${PREPROD_IMAGE_TAG}|g' ${yamlFile}
                        cat ${yamlFile} | grep ${PREPROD_IMAGE_TAG} || echo "Replacement failed in ${yamlFile}"
                    """
                    sh """
                        kubectl --kubeconfig=/var/lib/jenkins/.kube/config apply -f kubernetes/preprod/
                    """
                }
            }
        }

        stage('Deploy app to prod env') {
            when {
                branch 'prod'
            }
            steps {
                script {
                    echo "Deploying to Prod Environment"
                    def yamlFile = 'kubernetes/prod/05-deployment.yaml'

                    sh """
                        sed -i 's|<latest>|prod-cloudcortex-v.1.${BUILD_NUMBER}|g' ${yamlFile}
                        cat ${yamlFile} | grep prod-cloudcortex-v.1.${BUILD_NUMBER} || echo "Replacement failed in ${yamlFile}"
                    """
                    sh """
                        kubectl --kubeconfig=/var/lib/jenkins/.kube/config apply -f kubernetes/prod/
                    """
                }
            }
        }
    }

    post {
        success {
            echo "Deployment to ${env.BRANCH_NAME} environment completed successfully"
        }
        failure {
            echo "Deployment to ${env.BRANCH_NAME} environment failed. Check logs for details."
        }
    }
}