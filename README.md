# avd-azure

Part of [avd-ops](https://avd-ops.dev/), the open toolkit for Azure Virtual Desktop.

Azure ARM and Bicep infrastructure control plane (`avd-azure`), orchestrated by [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone#readme) ([avd-ops docs](https://avd-ops.dev/docs/repos/avd-azure.html), [decision 0009](https://avd-ops.dev/docs/decisions/0009-split-landing-zone-into-five-control-planes.html)).

> [!WARNING]
> **Personal project. Research and learning only. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time **for research and learning**. It is **not affiliated with, endorsed by or supported by my employer**, Liquidware or Microsoft, and it does not represent their views, products or guidance.
> - **Do not run any of it in production** or against subscriptions and tenants that matter. Test it first in a dedicated lab subscription and tenant.
> - It is provided **"as is", without warranty of any kind**, under the [MIT License](LICENSE). You use it at your own risk.
> - **Contributions and forks are welcome and encouraged.** See [Contributing](#contributing).

## How it connects

| Direction | Repo | Relationship |
|---|---|---|
| Front door | [avd-ops](https://github.com/avd-ops/avd-ops#readme) | Overview, [repo page](https://avd-ops.dev/docs/repos/avd-azure.html), and platform decisions |
| Orchestrator | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone#readme) | Invokes `avd-azure` to deploy AVD workspaces, host pools, storage, and hosts |
| Upstream | [avd-entra](https://github.com/avd-ops/avd-entra#readme) | Supplies `entra-manifest.json` group and Entra Kerberos readiness |
| Upstream | [avd-networking](https://github.com/avd-ops/avd-networking#readme) | Supplies `networking-outputs.json` (`C31`) when deployed in `HubPeered` mode |
| Upstream | [avd-migrate](https://github.com/avd-ops/avd-migrate#readme) | Supplies `C14` target-state manifests for baseline sizing |
| Downstream | [avd-intune](https://github.com/avd-ops/avd-intune#readme) | Enrolls joined session hosts via `AADLoginForWindows` |
| Downstream | [avd-power-platform](https://github.com/avd-ops/avd-power-platform#readme) | Consumes `azure-outputs.json` host pool and resource group references |
| Hybrid siblings | [avd-aws](https://github.com/avd-ops/avd-aws#readme) / [avd-gcp](https://github.com/avd-ops/avd-gcp#readme) | Optional AWS/GCP session-host control planes for AVD Hybrid |

## What it does

- Deploys multiple workspaces, Desktop and RemoteApp application groups, and Pooled or Personal host pools from Bicep.
- Configures full AVD Private Link (`connection`, `feed`, and `global`) and Private Endpoints for Azure Files and Key Vault.
- Deploys FSLogix on Premium Azure Files with Entra Kerberos and no storage keys; session hosts on Trusted Launch with encryption at host.
- Enrolls session hosts into [avd-intune](https://github.com/avd-ops/avd-intune#readme) on join via the `AADLoginForWindows` extension and binds application groups to [avd-entra](https://github.com/avd-ops/avd-entra#readme) groups.
- Checked in CI with PSRule for Azure and WDOT image optimization pinned by commit.

## Contracts

Consumes `entra-manifest.json` (and optional `C14` target-state manifests and `C31` `networking-outputs.json`) and produces `azure-outputs.json` (resource group, host pool ARM references, Private Link and delegated VNet subnet references).

## Docs

- Agent instructions & guardrails: [AGENTS.md](AGENTS.md)
- Repo page on avd-ops: [avd-ops.dev/docs/repos/avd-azure](https://avd-ops.dev/docs/repos/avd-azure.html)

## Contributing

Fork it, open an issue or a pull request. Follow the family guardrails in [AGENTS.md](AGENTS.md): no tenant IDs, secrets, domains or customer names, and propose changes via pull request only. Contributions are accepted under the [MIT License](LICENSE).

## License and disclaimer

[MIT](LICENSE). Personal project, not for production, provided as is, not affiliated with the author's employer, Liquidware or Microsoft.
