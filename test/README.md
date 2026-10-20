# Goat Pro tests

The existing metadata, constructor, ERC-20, and launch-transfer tests are retained.
`GoatProEdges.t.sol` adds allowance boundary transitions, caller/origin isolation,
self-transfers, failed transfers followed by valid retries, approval before receipt,
and delegated round trips for one wei, the full supply, and fuzzed amounts.

`GoatPro.invariant.t.sol` interleaves ten handler actions among four holders,
including expected failures and finite/infinite approval changes. After every
handler action it checks:

- Total supply stays at `1_000_000_000 * 10**18` and all balances remain accounted for.
- Each holder's balance plus cumulative payments equals its initial allocation
  plus cumulative receipts.
- Every holder/spender allowance equals its approval and successful-spending history.
  Failed calls must preserve both balances and allowances.

The histories come from call inputs, not the resulting token state. Only the handler
is targeted; token storage and balances are never edited with cheatcodes. Inline
settings run 1,000 cases per fuzz test and 256 invariant sequences of 128 actions,
with unexpected handler reverts treated as failures. A deterministic handler
sequence covers every action and verifies recovery after rejected calls.

Run from the repository root with the installed compiler and vendored dependencies:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xf814015270a398f4a9858e85a8cb353f41a76850778af0ff5c3b4bbe251cb39a forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The scratch output paths keep generated artifacts within the disposable test area.
No RPC, environment mutation, FFI, new dependencies, or configuration edits are needed.
The local launch fixture checks token movements; the supplied protected harness
performs the separate factory and Uniswap integration checks.
