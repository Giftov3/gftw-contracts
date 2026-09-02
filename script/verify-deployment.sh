#!/usr/bin/env bash
# Post-deploy verification for GFTW. READ-ONLY: sends no transactions, needs no key.
#
# Checks a live deployment against the frozen parameters in DEPLOYMENT_PARAMS.md
# and reports PASS/FAIL per gate.
#
# Usage:
#   ./script/verify-deployment.sh <rpc-url> [token-address] [safe-address]
#
#   mainnet:  ./script/verify-deployment.sh https://bsc-dataseed.binance.org
#   testnet:  ./script/verify-deployment.sh https://data-seed-prebsc-1-s1.binance.org:8545
#
# Addresses default to the published ones. Pass them explicitly if the deploy
# landed somewhere else (e.g. the CREATE2 salt was not used).
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

RPC=${1:?rpc url required}
TOKEN=${2:-0xD3D2c5Ab093a6aBa53EAbEA005D4226113C837F6}
SAFE=${3:-0xE26D92b34B8EB79d9B415605aAa46de47066a38B}

EXPECTED_SUPPLY=1000000000000000000000000000   # 1e27 = 1B * 1e18
OWNER1=0x5e3c8F996414CE298Fe35E25EaBf7F0553489818
OWNER2=0x917EE1837E277f03688414420043dD2240270605
OWNER3=0x3EF75a9c03EA8D5B31a926b00A8786eF69b4a08B

pass=0; fail=0
ok()   { echo "  [PASS] $1"; pass=$((pass+1)); }
bad()  { echo "  [FAIL] $1"; fail=$((fail+1)); }

echo "RPC:   $RPC"
CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null) || { echo "cannot reach RPC"; exit 1; }
case "$CHAIN" in
  56) NET="BSC MAINNET" ;;
  97) NET="BSC TESTNET" ;;
  *)  NET="chain $CHAIN (unexpected)" ;;
esac
echo "Chain: $CHAIN  ($NET)"
echo "Token: $TOKEN"
echo "Safe:  $SAFE"
echo

echo "== Safe =="
SAFE_CODE=$(cast code "$SAFE" --rpc-url "$RPC" 2>/dev/null)
if [ -n "$SAFE_CODE" ] && [ "$SAFE_CODE" != "0x" ]; then
  ok "Safe contract exists at $SAFE"

  OWNERS=$(cast call "$SAFE" 'getOwners()(address[])' --rpc-url "$RPC" 2>/dev/null)
  echo "         owners: $OWNERS"
  for O in "$OWNER1" "$OWNER2" "$OWNER3"; do
    if echo "$OWNERS" | grep -qi "${O#0x}"; then ok "owner present: $O"
    else bad "owner MISSING: $O"; fi
  done

  TH=$(cast call "$SAFE" 'getThreshold()(uint256)' --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  [ "$TH" = "2" ] && ok "threshold == 2" || bad "threshold == ${TH:-?}, expected 2"
else
  bad "NO CONTRACT at $SAFE — the Safe is not deployed on this chain"
fi

echo
echo "== Token =="
TOKEN_CODE=$(cast code "$TOKEN" --rpc-url "$RPC" 2>/dev/null)
if [ -n "$TOKEN_CODE" ] && [ "$TOKEN_CODE" != "0x" ]; then
  ok "token contract exists at $TOKEN"

  NAME=$(cast call "$TOKEN" 'name()(string)' --rpc-url "$RPC" 2>/dev/null | tr -d '"')
  SYM=$(cast call "$TOKEN" 'symbol()(string)' --rpc-url "$RPC" 2>/dev/null | tr -d '"')
  DEC=$(cast call "$TOKEN" 'decimals()(uint8)' --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  [ "$NAME" = "Giftworld" ] && ok "name == Giftworld" || bad "name == ${NAME:-?}"
  [ "$SYM" = "GFTW" ]       && ok "symbol == GFTW"     || bad "symbol == ${SYM:-?}"
  [ "$DEC" = "18" ]         && ok "decimals == 18"     || bad "decimals == ${DEC:-?}"

  SUPPLY=$(cast call "$TOKEN" 'totalSupply()(uint256)' --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  [ "$SUPPLY" = "$EXPECTED_SUPPLY" ] \
    && ok "totalSupply == 1B" \
    || bad "totalSupply == ${SUPPLY:-?}, expected $EXPECTED_SUPPLY"

  BAL=$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "$SAFE" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  if [ "$BAL" = "$EXPECTED_SUPPLY" ]; then
    ok "Safe holds 100% of supply"
  else
    bad "Safe holds ${BAL:-?}, expected $EXPECTED_SUPPLY"
    echo "         ^ CRITICAL: supply is not where it should be. Find out where it went."
  fi

  # No mint/owner/pause should exist. These must all revert or return nothing.
  for SIG in 'owner()(address)' 'paused()(bool)'; do
    if cast call "$TOKEN" "$SIG" --rpc-url "$RPC" >/dev/null 2>&1; then
      bad "$SIG responded — expected NO such function on an ownerless token"
    else
      ok "$SIG absent, as expected"
    fi
  done
else
  bad "NO CONTRACT at $TOKEN — the token is not deployed on this chain"
fi

echo
echo "== Result =="
echo "  $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "  DO NOT ANNOUNCE THIS DEPLOYMENT until every gate passes."
  exit 1
fi
echo "  All gates passed."
[ "$CHAIN" = "56" ] && echo "  Mainnet: confirm BscScan source verification before publishing the address."
exit 0
