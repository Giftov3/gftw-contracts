# Official Deployment Parameters — ESTABLISHED 2026-07-27

These addresses are established by CREATE2 pre-computation. They are final and
publishable **provided the frozen inputs below never change**. Verified by two
independent computations (forge `vm.computeCreate2Address` and `cast create2`).

## The addresses

| What | Address |
|---|---|
| **Treasury / distribution Safe (2-of-3)** | `0xE26D92b34B8EB79d9B415605aAa46de47066a38B` |
| **GFTW token** | `0xD3D2c5Ab093a6aBa53EAbEA005D4226113C837F6` |

## Frozen inputs — changing ANY of these silently changes the addresses

### Safe (BSC mainnet, canonical v1.4.1 contracts)
- Factory: `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67` (`createProxyWithNonce`)
- Singleton: SafeL2 `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762`
- Fallback handler: `0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99`
- Initial owners (cold wallets, exact order matters):
  1. `0x5e3c8F996414CE298Fe35E25EaBf7F0553489818`
  2. `0x917EE1837E277f03688414420043dD2240270605`
  3. `0x3EF75a9c03EA8D5B31a926b00A8786eF69b4a08B`
- Threshold: **2**
- saltNonce: **44384351** (the block of the Nov 27 2024 mint)
- Owners/threshold MAY be changed after deployment via the Safe itself (per the
  whitepaper §13 signer-set publication) — that does NOT change the address.
  Only the *initial* setup above is address-critical.

### GFTW token
- Deployed via the deterministic CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C`
  (what `forge script` uses when `SALT` is set)
- Constructor arg (distributor): the Safe address above
- SALT: **44384351**
- **`src/GFTW.sol` is FROZEN** — any bytecode change (code, imports, OZ version) changes the address
- **Compiler settings are FROZEN** (foundry.toml): solc `0.8.28`, optimizer on,
  `optimizer_runs = 10_000`, `evm_version = cancun`
- Re-verify any time:
  `DISTRIBUTOR=0xE26D92b34B8EB79d9B415605aAa46de47066a38B SALT=44384351 forge script script/Deploy.s.sol:ComputeTokenAddress`

## Deployment (when the time comes)

1. Safe first — any funded key may send it; owners need not:
   `OWNERS=<the 3 above, same order> THRESHOLD=2 SALT_NONCE=44384351 ./script/compute-safe-address.sh`
   prints the exact `createProxyWithNonce` call + initializer. Send it, then verify
   the deployed address equals `0xE26D…a38B` and `getOwners()`/`getThreshold()` match.
2. Token second:
   `DISTRIBUTOR=0xE26D92b34B8EB79d9B415605aAa46de47066a38B SALT=44384351 forge script script/Deploy.s.sol:DeployToken --rpc-url bsc --broadcast --verify --ledger`
   Verify the deployed address equals `0xD3D2…37F6` and `balanceOf(safe) == 1e27`
   **before announcing anything**.

The same inputs produce the same addresses on BSC testnet (all four canonical
factory/singleton contracts exist there) — so the testnet rehearsal can use the
production parameters and land on the production addresses, chain id 97.
