/**
 * Copyright (c) 2020 Gitpod GmbH. All rights reserved.
 * Licensed under the MIT License. See License-MIT.txt in the project root for license information.
 */

# Derived from https://learn.hashicorp.com/terraform/kubernetes/provision-eks-cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name                 = var.vpc.name
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${var.kubernetes.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.kubernetes.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                               = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.kubernetes.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                      = "1"
  }
}

module "kubernetes" {
  source  = "terraform-aws-modules/eks/aws"
  version = "13.2.1"
  #make this into a for-loop with values from auto.tfvars
  map_users  = [
    { "groups": [ "system:masters" ], "userarn": "arn:aws:iam::060260394319:user/dmitry.moskalets", "username": "dmitry.moskalets" },
    { "groups": [ "system:masters" ], "userarn": "arn:aws:iam::060260394319:user/pavan.v", "username": "pavan.v" },
  ]
  cluster_name       = var.kubernetes.cluster_name
  cluster_version    = var.kubernetes.version
  subnets            = module.vpc.public_subnets
  write_kubeconfig   = true
  config_output_path = "${var.kubernetes.home_dir}/.kube/config"
  vpc_id             = module.vpc.vpc_id

  worker_groups = [
    {
      instance_type     = var.kubernetes.instance_type
      asg_max_size      = var.kubernetes.max_node_count
      asg_min_size      = var.kubernetes.min_node_count
      placement_tenancy = "default"
      kubelet_extra_args   = "--node-labels=gitpod.io/workload_meta=true" 
      tags = [
        # These tags are required for the cluster-autoscaler to discover this ASG
        {
          "key"                 = "k8s.io/cluster-autoscaler/${var.kubernetes.cluster_name}"
          "value"               = "true"
          "propagate_at_launch" = true
        },
        {
          "key"                 = "k8s.io/cluster-autoscaler/enabled"
          "value"               = "true"
          "propagate_at_launch" = true
        },
        {
          "key"                 = "gitpod.io/workload_meta"
          "value"               = "true"
          "propagate_at_launch" = true
        }
      ]
    },
    {
      instance_type     = var.kubernetes.workspace_worker_group.instance_type
      asg_max_size      = var.kubernetes.workspace_worker_group.max_node_count
      asg_min_size      = var.kubernetes.workspace_worker_group.min_node_count
      placement_tenancy = "default"
      kubelet_extra_args   = "--node-labels=gitpod.io/workload_workspace=true" 
      tags = [
        # These tags are required for the cluster-autoscaler to discover this ASG
        {
          "key"                 = "k8s.io/cluster-autoscaler/${var.kubernetes.cluster_name}"
          "value"               = "true"
          "propagate_at_launch" = true
        },
        {
          "key"                 = "k8s.io/cluster-autoscaler/enabled"
          "value"               = "true"
          "propagate_at_launch" = true
        },
        {
          "key"                 = "gitpod.io/workload_workspace"
          "value"               = "true"
          "propagate_at_launch" = true
        }
      ]
    }
  ]
}

resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name $CLUSTER"
    environment = {
      CLUSTER = var.kubernetes.cluster_name
    }
  }
  depends_on = [
    module.kubernetes
  ]
}


# Autoscaling for a cluster created with "terraform-aws-modules/eks/aws"
# Source: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/autoscaling.md
resource "aws_iam_role_policy_attachment" "workers_autoscaling" {
  policy_arn = aws_iam_policy.worker_autoscaling.arn
  role       = module.kubernetes.worker_iam_role_name #[0]
}

resource "aws_iam_policy" "worker_autoscaling" {
  name_prefix = "eks-worker-autoscaling-${module.kubernetes.cluster_id}"
  description = "EKS worker node autoscaling policy for cluster ${module.kubernetes.cluster_id}"
  policy      = data.aws_iam_policy_document.worker_autoscaling.json
  #   path        = var.iam_path
}

data "aws_iam_policy_document" "worker_autoscaling" {
  statement {
    sid    = "eksWorkerAutoscalingAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "eksWorkerAutoscalingOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${module.kubernetes.cluster_id}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}



# Loosely following: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/autoscaling.md
# https://www.terraform.io/docs/providers/helm/r/release.html
resource "helm_release" "autoscaler" {
  name       = "cluster-autoscaler-rel"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  namespace        = "cluster-autoscaler"
  create_namespace = true
  recreate_pods    = true
  wait             = true

  values = [
    # TODO [geropl] Make sure the tag below is in line with var.kubernetes.version and references a valid (minor) version
    <<-EOT
      rbac:
        create: true

      cloudProvider: aws
      awsRegion: ${var.aws.region}

      autoDiscovery:
        clusterName: ${var.kubernetes.cluster_name}
        enabled: true

      image:
        repository: eu.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler
        tag: v1.16.5
    EOT
  ]

  depends_on = [
    module.kubernetes
  ]
}


module "cert-manager" {
  source          = "./modules/https"
  gitpod-node-arn = module.kubernetes.worker_iam_role_arn
  cluster_name    = module.kubernetes.cluster_id
  dns             = var.dns
  aws             = var.aws
  cert_manager    = var.cert_manager
  gitpod          = var.gitpod

  project = var.project

  providers = {
    local   = local
    kubectl = kubectl
  }
}

module "database" {
  source = "./modules/mysql"

  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnets
  security_group_id = module.kubernetes.worker_security_group_id
  database          = var.database

  project = var.project
  gitpod  = var.gitpod

}



module "registry" {
  source               = "./modules/registry"
  project              = var.project
  gitpod               = var.gitpod
  region               = var.aws.region
  worker_iam_role_name = module.kubernetes.worker_iam_role_name

  depends_on = [module.kubernetes.cluster_id]
}

module "storage" {
  source               = "./modules/storage"
  project              = var.project
  region               = var.aws.region
  worker_iam_role_name = module.kubernetes.worker_iam_role_name
  vpc_id               = module.vpc.vpc_id

  depends_on = [
    module.kubernetes.cluster_id
  ]
}



#
# Gitpod
#

module "gitpod" {
  source       = "./modules/gitpod"
  gitpod       = var.gitpod
  domain_name  = var.dns.domain
  cluster_name = module.kubernetes.cluster_id

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  auth_providers = var.auth_providers

  helm = {
    repository = "${path.root}/../../"
    chart      = "chart"
  }

  values = [
    module.registry.values,
    module.storage.values,
    module.database.values
  ]

  depends_on = [
    module.kubernetes.cluster_id,
    module.cert-manager.ready
  ]
}


module "route53" {
  source       = "./modules/route53"
  dns          = var.dns
  external_dns = module.gitpod.external_dns
}
