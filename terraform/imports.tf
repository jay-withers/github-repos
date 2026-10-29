# Resource groups that consumers created themselves, taken over when their
# entry gets `create_resource_groups`. Once applied, an import here is a
# no-op; delete it in a later change. The consumer's own repo then drops the
# group with `removed { lifecycle { destroy = false } }` - after this apply,
# so the group is never unmanaged.

import {
  to = azurerm_resource_group.deploy["market-agent-rg-marketagent-dev"]
  id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-marketagent-dev"
}
