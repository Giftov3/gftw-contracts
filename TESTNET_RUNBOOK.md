# BSC Testnet Deployment Runbook (chain 97)

Written 2026-08-19. Scope: **Safe + GFTW token only.** The other four contracts
take immutable timestamps that have not been chosen yet.

Offline state at time of writing, all verified:
- `forge test` → 67 passed, 1 skipped, 0 failed
- `./script/rehearsal.sh` → PASSED, full runbook exercised on anvil
- `ComputeTokenAddress` → `0xD3D2c5Ab093a6aBa53EAbEA005D4226113C837F6`, matches DEPLOYMENT_PARAMS.md
- `git status` clean; `src/` and `foundry.toml` unchanged since the addresses were frozen

---

## Why testnet is worth doing even though the rehearsal passed

The anvil rehearsal injected Safe bytecode at the canonical addresses. It proved the
*logic*. It did not prove the three things that actually break on deploy day:

1. The **real Safe v1.4.1 factory** accepting our initializer at `saltNonce 44384351`
2. **Signing and broadcasting** from a real key against a real RPC
3. **BscScan verification** producing a green checkmark against our exact compiler settings

Testnet uses the same frozen inputs, so it lands on the **same addresses** as mainnet
will. That makes it a true dress rehearsal, and it is the last untested layer.

**Deploying on testnet does not consume the mainnet addresses.** Chains are
independent. Nothing here is a point of no return.

---

## Prerequisites (all currently missing)

| # | Item | Notes |
|---|---|---|
| 1 | **Deployer address + tBNB** | Any funded key. It does NOT need to be a Safe owner. ~0.1 tBNB is plenty. Faucet: https://testnet.bnbchain.org/faucet-smart |
| 2 | **Signing method** | For testnet a throwaway hot key is acceptable. **It must never be reused on mainnet.** Mainnet uses `--ledger`. |
| 3 | **`BSCSCAN_API_KEY`** | Needed for `--verify`. Not currently set in the environment. |
| 4 | **The three owner addresses** | Use the real cold wallets from DEPLOYMENT_PARAMS.md. Deploying a Safe that owns nothing on testnet is harmless, and it is the only way to land on the production address. |

Export before starting:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
export RPC=https://data-seed-prebsc-1-s1.binance.org:8545
export BSCSCAN_API_KEY=<key>
export OWNERS=0x5e3c8F996414CE298Fe35E25EaBf7F0553489818,0x917EE1837E277f03688414420043dD2240270605,0x3EF75a9c03EA8D5B31a926b00A8786eF69b4a08B
```

---

## Step 0 — confirm the CREATE2 deployer exists on testnet

`DeployToken` with a `SALT` routes through the universal deterministic deployer.
If it is absent, the deploy silently produces a different address.

```bash
cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url $RPC | head -c 20
```

**Gate:** must return bytecode, not `0x`. If it returns `0x`, stop and report back.

---

## Step 1 — predict the Safe address

```bash
OWNERS=$OWNERS THRESHOLD=2 SALT_NONCE=44384351 \
  ./script/compute-safe-address.sh $RPC
```

**Gate:** printed address must equal `0xE26D92b34B8EB79d9B415605aAa46de47066a38B`.

If it does not, **stop**. Something in the owner list, its order, or the threshold has
drifted from the frozen inputs, and continuing would mint 1B tokens to the wrong place.
Do not "fix" it by adopting the new address.

Keep the `initializer` hex it prints. Step 2 needs it verbatim.

---

## Step 2 — deploy the Safe

```bash
cast send 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67 \
  'createProxyWithNonce(address,bytes,uint256)' \
  0x29fcB43b46531BcA003ddC8FCB67FFE91900C762 \
  <initializer-from-step-1> \
  44384351 \
  --rpc-url $RPC --private-key <testnet-key>
```

---

## Step 3 — verify the Safe before going anywhere near the token

```bash
SAFE=0xE26D92b34B8EB79d9B415605aAa46de47066a38B
cast code $SAFE --rpc-url $RPC | head -c 20          # must be non-empty
cast call $SAFE 'getOwners()(address[])' --rpc-url $RPC
cast call $SAFE 'getThreshold()(uint256)' --rpc-url $RPC
```

**Gates, all three must hold:**
- code is non-empty at exactly `0xE26D…a38B`
- `getOwners()` returns the three expected addresses
- `getThreshold()` returns `2`

This is the checkpoint that matters. The token mint is irreversible and goes wherever
this address points.

---

## Step 4 — dry run the token (no broadcast)

```bash
DISTRIBUTOR=$SAFE SALT=44384351 \
  forge script script/Deploy.s.sol:DeployToken --rpc-url $RPC
```

**Gate:** no revert. In particular the `require(distributor.code.length > 0)` on
[Deploy.s.sol:22](script/Deploy.s.sol#L22) must pass, which it only will if step 2 landed.

---

## Step 5 — deploy the token

```bash
DISTRIBUTOR=$SAFE SALT=44384351 \
  forge script script/Deploy.s.sol:DeployToken \
  --rpc-url $RPC --broadcast --verify
```

---

## Step 6 — final verification

```bash
TOKEN=0xD3D2c5Ab093a6aBa53EAbEA005D4226113C837F6
cast call $TOKEN 'name()(string)'      --rpc-url $RPC   # Giftworld
cast call $TOKEN 'symbol()(string)'    --rpc-url $RPC   # GFTW
cast call $TOKEN 'decimals()(uint8)'   --rpc-url $RPC   # 18
cast call $TOKEN 'totalSupply()(uint256)' --rpc-url $RPC # 1000000000000000000000000000
cast call $TOKEN "balanceOf(address)(uint256)" $SAFE --rpc-url $RPC # same, 1e27
```

**Gates:**
- deployed address is exactly `0xD3D2…37F6`
- `balanceOf(safe) == totalSupply() == 1e27` (the Safe holds 100% of supply)
- BscScan testnet shows the contract **verified**

---

## Abort conditions

Stop and reassess if any of these occur. None are recoverable by pushing forward.

- Predicted Safe address ≠ `0xE26D…a38B` at step 1
- `getOwners()` or `getThreshold()` mismatch at step 3
- Deployed token address ≠ `0xD3D2…37F6` at step 6
- `balanceOf(safe)` ≠ `1e27`
- BscScan verification fails (means the compiler settings drifted, which means the
  mainnet address is also wrong)

---

## After a green testnet run

The remaining mainnet prerequisites are non-technical:

1. **Ledger** set up and funded with real BNB for the mainnet deploy
2. **Confirmation that the three cold wallets are held by three separate parties**, since
   whitepaper §13 states this as fact
3. The **audit engagement**, which gates everything downstream of deployment

Deploying the token on mainnet does not open migration. Registration and claim windows
live in contracts that cannot deploy until the TGE timestamps are chosen.
