# Contracts for avd-azure

Pins `cloud-environments.json` (`C26: avd-cloud-environments/v1` from `avd-assess`), consumes `entra-manifest.json` (and optional C14 target-state manifests), and produces `azure-outputs.json` (`cloud`: `"commercial"` | `"usgov"`, `complianceProfile`: `"standard"` | `"itar-cui"`, resource group, host pool ARM references, Private Link and delegated VNet subnet references).

See [avd-ops decision 0009](https://avd-ops.dev/docs/decisions/0009-split-landing-zone-into-five-control-planes.html) and [avd-ops decision 0013](https://github.com/avd-ops/avd-ops/blob/main/docs/knowledge/decisions/0013-azure-us-government-and-gcc-high-support.md).
