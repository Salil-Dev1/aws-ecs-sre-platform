locals {
  atlas_provider_region_name = var.aws_region == "ap-south-1" ? "AP_SOUTH_1" : (
    var.aws_region == "us-east-1" ? "US_EAST_1" : upper(replace(var.aws_region, "-", "_"))
  )
}

resource "random_password" "mongo" {
  length  = 24
  special = false
}

resource "mongodbatlas_cluster" "taskflow" {
  project_id                   = var.atlas_project_id
  name                         = "${var.project_name}-cluster"
  cluster_type                 = "REPLICASET"
  provider_name                = "TENANT"
  backing_provider_name        = "AWS"
  provider_region_name         = local.atlas_provider_region_name
  provider_instance_size_name  = "M0"
  auto_scaling_disk_gb_enabled = false
}

resource "mongodbatlas_database_user" "taskflow" {
  project_id         = var.atlas_project_id
  username           = "${var.project_name}-app"
  password           = random_password.mongo.result
  auth_database_name = "admin"

  roles {
    role_name     = "readWrite"
    database_name = "taskflowdb"
  }
}

resource "mongodbatlas_project_ip_access_list" "ecs" {
  project_id = var.atlas_project_id
  cidr_block = "0.0.0.0/0"
  comment    = "TaskFlow ECS has no NAT or fixed outbound IPs; public access is required for M0."
}

resource "aws_ssm_parameter" "mongo_uri" {
  name        = "/${var.project_name}/prod/mongo_uri"
  description = "MongoDB Atlas connection URI injected into TaskFlow backend tasks."
  type        = "SecureString"
  value = format(
    "%s/taskflowdb?retryWrites=true&w=majority",
    trimsuffix(
      replace(
        mongodbatlas_cluster.taskflow.connection_strings[0].standard_srv,
        "mongodb+srv://",
        "mongodb+srv://${mongodbatlas_database_user.taskflow.username}:${random_password.mongo.result}@",
      ),
      "/",
    ),
  )
}
