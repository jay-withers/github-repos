# The containers scripts/bootstrap-state.ps1 created before state.tf managed
# them. Delete this file in a later change, once it has applied.
import {
  for_each = toset([
    "azure-container-apps",
    "repo-agent",
    "gym-log",
    "finances",
    "career",
    "security-testing",
    "market-agent",
    "observability",
  ])

  to = azurerm_storage_container.consumer[each.key]
  id = "${data.azurerm_storage_account.state.id}/blobServices/default/containers/${each.key}"
}
