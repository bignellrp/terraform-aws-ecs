provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

locals {
  region = "eu-west-2"
  name   = "ex-${basename(path.cwd)}"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = "ecs-frontend"
  container_port = 3000

  tags = {
    Name       = local.name
    Example    = local.name
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-ecs"
  }
}

################################################################################
# Cluster
################################################################################

module "ecs_cluster" {
  source = "../../modules/cluster"

  cluster_name = local.name

  # Capacity provider
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  tags = local.tags
}

################################################################################
# Service
################################################################################

module "ecs_service" {
  source = "../../modules/service"

  name        = local.name
  cluster_arn = module.ecs_cluster.arn

  cpu    = 1024
  memory = 4096

  #Container definition(s)
  container_definitions = {

    # fluent-bit = {
    #   cpu       = 512
    #   memory    = 1024
    #   essential = true
    #   image     = nonsensitive(data.aws_ssm_parameter.fluentbit.value)
    #   firelens_configuration = {
    #     type = "fluentbit"
    #   }
    #   memory_reservation = 50
    #   user               = "0"
    # }

    footyapp = {
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "516399821737.dkr.ecr.eu-west-2.amazonaws.com/footyapp-repository:latest"
      memory_reservation = 50
      user               = "0"
    }

    (local.container_name) = {
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "516399821737.dkr.ecr.eu-west-2.amazonaws.com/footyapp-repository:latest"
      port_mappings = [
        {
          name          = local.container_name
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "SPREADSHEET_ID"
          value = "value1"
        },
        {
          name  = "ENV_VARIABLE_NAME2"
          value = "value2"
        },
        # {
        #   name  = "DB_PASSWORD"
        #   value_from = "/myapp/db_password" # Reference to the secret in SSM Parameter Store
        # },
        # Add more environment variables as needed
      ]

      # Example image used requires access to write to root filesystem
      #readonly_root_filesystem = false

      dependencies = [{
        containerName = "footyapp"
        condition     = "START"
      }]

      #enable_cloudwatch_logging = True
      # log_configuration = {
      #   logDriver = "awsfirelens"
      #   options = {
      #     Name                    = "firehose"
      #     region                  = local.region
      #     delivery_stream         = "my-stream"
      #     log-driver-buffer-limit = "2097152"
      #   }
      # }
      log_configuration = {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/footyapp-service"
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "footyapp-container"
        }
      }
      memory_reservation = 100
    }
  }

  service_connect_configuration = {
    namespace = aws_service_discovery_http_namespace.this.arn
    service = {
      client_alias = {
        port     = local.container_port
        dns_name = local.container_name
      }
      port_name      = local.container_name
      discovery_name = local.container_name
    }
  }

  load_balancer = {
    service = {
      target_group_arn = element(module.alb.target_group_arns, 0)
      container_name   = local.container_name
      container_port   = local.container_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_ingress_3000 = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb_sg.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.tags
}

################################################################################
# # ChatGPT Example Task and Service
# ################################################################################

# module "ecs_cluster" {
#   source = "terraform-aws-modules/ecs/aws"
#   version = "3.0.0"

#   name = "my-ecs-cluster"
#   #subnets = module.vpc.private_subnets_cidr_blocks # Replace these with your desired subnets e.g ["subnet-12345678", "subnet-87654321"]
# }

# resource "aws_ecr_repository" "footyapp_repository" {
#   name = "footyapp-repository"
# }

# resource "aws_ecs_task_definition" "footyapp_task" {
#   family = "footyapp-task"
#   container_definitions = jsonencode([
#     {
#       name  = "footyapp-container"
#       image = "516399821737.dkr.ecr.eu-west-2.amazonaws.com/footyapp-repository:latest"
#       port_mappings = {
#         container_port = 80
#         host_port      = 80
#       }
#       environment = [
#         {
#           name  = "SPREADSHEET_ID"
#           value = "value1"
#         },
#         {
#           name  = "ENV_VARIABLE_NAME2"
#           value = "value2"
#         },
#         # {
#         #   name  = "DB_PASSWORD"
#         #   value_from = "/myapp/db_password" # Reference to the secret in SSM Parameter Store
#         # },
#         # Add more environment variables as needed
#       ]
#     }
#     # Add more container definitions if needed for multiple containers in the task
#   ])
# }

# resource "aws_ecs_service" "footyapp_service" {
#   name            = "footyapp-service"
#   cluster         = module.ecs_cluster.cluster_id
#   task_definition = aws_ecs_task_definition.footyapp_task.arn
#   desired_count   = 1
#   iam_role        = module.ecs_cluster.ecs_task_execution_role_arn

#   deployment_minimum_healthy_percent = 50
#   deployment_maximum_percent         = 200

#   load_balancer = {
#     service = {
#       target_group_arn = element(module.alb.target_group_arns, 0)
#       container_name   = "footyapp-container"
#       container_port   = 80
#     }
#   }

#   subnet_ids = module.vpc.private_subnets
#   security_group_rules = {
#     alb_ingress_3000 = {
#       type                     = "ingress"
#       from_port                = 80
#       to_port                  = 80
#       protocol                 = "tcp"
#       description              = "Service port"
#       source_security_group_id = module.alb_sg.security_group_id
#     }
#     egress_all = {
#       type        = "egress"
#       from_port   = 0
#       to_port     = 0
#       protocol    = "-1"
#       cidr_blocks = ["0.0.0.0/0"]
#     }
#   }

#   tags = local.tags
# }

################################################################################
# Supporting Resources
################################################################################

# data "aws_ssm_parameter" "fluentbit" {
#   name = "/aws/service/aws-for-fluent-bit/stable"
# }

resource "aws_service_discovery_http_namespace" "this" {
  name        = local.name
  description = "CloudMap namespace for ${local.name}"
  tags        = local.tags
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-service"
  description = "Service security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  tags = local.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = local.name

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.alb_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name             = "${local.name}-footyapp-container"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
    },
  ]

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}
