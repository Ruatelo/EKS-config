# ECR Repository for the vulnerable application image
resource "aws_ecr_repository" "vulnerable_app" {
  name                 = "scenario1-vulnerable-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Scenario = "scenario1-eks-privesc"
  }
}

# Build and push the Docker image to ECR
resource "null_resource" "docker_build_push" {
  triggers = {
    app_hash          = filesha256("${path.module}/../vulnerable-app/app.py")
    dockerfile_hash   = filesha256("${path.module}/../vulnerable-app/Dockerfile")
    requirements_hash = filesha256("${path.module}/../vulnerable-app/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
      aws ecr get-login-password --region ${var.region} \
        | docker login --username AWS --password-stdin \
          "$ACCOUNT_ID.dkr.ecr.${var.region}.amazonaws.com"
      docker build -t scenario1-vulnerable-app ${path.module}/../vulnerable-app/
      docker tag scenario1-vulnerable-app:latest ${aws_ecr_repository.vulnerable_app.repository_url}:latest
      docker push ${aws_ecr_repository.vulnerable_app.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.vulnerable_app]
}
