# Resource groups that consumers created themselves, taken over when their
# entry gets `create_resource_groups`. Once applied, an import here is a
# no-op; delete it in a later change. The consumer's own repo then drops the
# group with `removed { lifecycle { destroy = false } }` - after this apply,
# so the group is never unmanaged.

import {
  to = azurerm_resource_group.deploy["repo-agent-rg-repoagent-dev"]
  id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-repoagent-dev"
}

import {
  to = azurerm_resource_group.deploy["gym-log-rg-gymlog-dev"]
  id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-gymlog-dev"
}

import {
  to = azurerm_resource_group.deploy["finances-rg-finances-dev"]
  id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-finances-dev"
}

import {
  to = azurerm_resource_group.deploy["career-rg-career-dev"]
  id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-career-dev"
}

import {
  to = azurerm_resource_group.deploy["security-testing-rg-sectest-dev"]
  id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-sectest-dev"
}
