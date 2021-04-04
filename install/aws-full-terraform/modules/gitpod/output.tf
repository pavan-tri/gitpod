/**
 * Copyright (c) 2020 Gitpod GmbH. All rights reserved.
 * Licensed under the MIT License. See License-MIT.txt in the project root for license information.
 */

output "external_dns" {
  value = data.kubernetes_service.proxy.status.0.load_balancer.0.ingress.0.hostname
}
