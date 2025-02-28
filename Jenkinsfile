pipeline {
    agent any

    environment {
        AWS_REGION = "us-east-1"
        S3_BUCKET = "dr-snapshots-bucket"
        INSTANCE_ID = ""  // This will be set dynamically
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main', url: 'https://github.com/vibhuti2023/terraform-dr2.git'
            }
        }
    stage('Inject SSH Key') {
            steps {
                withCredentials([string(credentialsId: 'SSH_PUBLIC_KEY', variable: 'SSH_KEY')]) {
                    sh '''
                    mkdir -p ~/.ssh
                    echo "$SSH_KEY" > ~/.ssh/id_rsa.pub
                    chmod 600 ~/.ssh/id_rsa.pub
                    '''
                }
            }
        }
        stage('Initialize Terraform') {
            steps {
                sh '''
                terraform init
                terraform validate
                '''
            }
        }

        stage('Apply Terraform') {
            steps {
                sh '''
                terraform apply -auto-approve
                INSTANCE_ID=$(terraform output -raw primary_instance_id)
                echo "INSTANCE_ID=$INSTANCE_ID" >> $GITHUB_ENV
                '''
            }
        }

        stage('Monitor & Backup') {
            steps {
                script {
                    while (true) {
                        def status = sh(script: "aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceState.Name' --output text", returnStdout: true).trim()
                        
                        if (status != "running") {
                            echo "Instance is down! Creating snapshot and triggering recovery..."
                            sh '''
                            SNAPSHOT_ID=$(aws ec2 create-snapshot --volume-id $(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[*].Instances[*].BlockDeviceMappings[*].Ebs.VolumeId' --output text) --description "DR Backup" --query 'SnapshotId' --output text)
                            aws ec2 deregister-image --image-id $(terraform output -raw backup_ami_id)
                            NEW_AMI_ID=$(aws ec2 create-image --instance-id $INSTANCE_ID --name "Backup_AMI" --query 'ImageId' --output text)
                            terraform apply -auto-approve -var "ami_id=$NEW_AMI_ID"
                            '''
                        } else {
                            echo "Instance is healthy. Next check in 15 minutes."
                        }
                        sleep 900 // 15 minutes
                    }
                }
            }
        }

        stage('Cleanup') {
            when {
                expression { return params.CLEANUP }
            }
            steps {
                sh 'terraform destroy -auto-approve'
            }
        }
    }

    parameters {
        booleanParam(name: 'CLEANUP', defaultValue: false, description: 'Destroy all resources')
    }
}
