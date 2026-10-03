Resolution: main's client contract (schema/surface/manifest/.zpkg.toml targets) is a strict superset of this PR's
snapshot, so it was kept as the contract; this PR's source hardening was kept; the per-target contract
fingerprints were regenerated with main's scripts/harden_client_contract.py so they describe the merged sources.
