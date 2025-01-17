/**
 * Copyright (c) 2020 Gitpod GmbH. All rights reserved.
 * Licensed under the MIT License. See License-MIT.txt in the project root for license information.
 */

variable "project" {
  type = object({
    name = string
  })
  default = {
    name = "self-hosted"
  }
}

variable "gitpod" {
  type = object({
    namespace  = string
    valueFiles = list(string)
  })
  default = {
    namespace  = "default"
    valueFiles = ["./values.yml"]
  }
}

variable "aws" {
  type = object({
    region  = string
    profile = string
  })
  default = {
    region  = "us-east-2"
    profile = "default"
  }
}

variable "kubernetes" {
  type = object({
    cluster_name   = string
    home_dir       = string
    version        = string
    autoscaler     = string
    instance_type  = string
    min_node_count = number
    max_node_count = number
    sysmasters     = list(string)
    workspace_worker_group = object({
      min_node_count = number
      max_node_count = number
      instance_type  = string
    })
  
  })
  default = {
    cluster_name   = "gitpod-cluster"
    version        = "1.16"
    autoscaler     = "1.16.5"
    min_node_count = 1
    max_node_count = 1
    instance_type = "m4.large"
    home_dir      = "/home/gitpod"
    sysmasters    = []
    workspace_worker_group = {
      min_node_count = 1
      max_node_count = 1
      instance_type  = "m4.large"
    }
  }
}

variable "dns" {
  type = object({
    domain    = string
    zone_name = string
  })
}

variable "cert_manager" {
  type = object({
    chart     = string
    email     = string
    namespace = string
  })
}


variable "database" {
  type = object({
    name           = string
    port           = number
    instance_class = string
    engine_version = string
    user_name      = string
    password       = string
  })
  default = {
    name           = "gitpod"
    user_name      = "gitpod"
    password       = ""
    engine_version = "5.7.26"
    port           = 3306
    instance_class = "db.t2.micro"
  }
}


variable "auth_providers" {
  type = list(
    object({
      id            = string
      host          = string
      client_id     = string
      client_secret = string
      settings_url  = string
      callback_url  = string
      protocol      = string
      type          = string
    })
  )
}

variable "vpc" {
  type = object({
    name = string
  })
  default = {
    name = "gitpod-network"
  }
}
