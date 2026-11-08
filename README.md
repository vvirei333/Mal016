# TendieTool — PosterBoard/MobileGestalt CLI for jailbroken iOS 16.x

Jailbreak utility (Dopamine/root) — **no exploits**. TendieTool uses the root
access you already have to do what exploit tools (BQEscape/3105) do through
bugs. Target: iPhone 8+ (A11), iOS 16.7.16.

## Why a separate tool
- BQTool/Nugget/3105 target iOS 17+ or need kernel exploits (none for 16.7.x —
  kfd patched). On a jailbroken device the exploit layer is unnecessary.
- Research value: nobody tested PosterBoard 16.x vs 17+ `.tendies` packs.
  TendieTool logs exactly which descriptor fields 16.x accepts/rejects.

## Commands (v0.1 plan)
    tendietool recon                 # identity + paths (RECON-first!)
    tendietool gestalt dump|get K|set K V|rm K
    tendietool gestalt backup|restore
    tendietool tendie inspect X.tendies
    tendietool tendie import X.tendies [--reset]

## Log
Documents/tendietool.log; header always: hw.machine + kern.osrelease
(lesson from the newjail runs: logs without identity are unattributable).

## Build
Linux cross-compile, same pipeline as ABrake27 ASTCProbe (clang → ld64.lld
→ ldid). See build_tendietool.sh.

## References
- SerStars/Nugget-Wallpapers — open .tendies catalog (111+ packs)
- leminlimez/CowabungaLite — partial-restore architecture (iOS 15+, no tendies)
- YangJiiii/3105 — PosterBoard lab on 17+ (Geod-MCM), feature reference
- ABrake27 research/intel/mcm/BQ272_MCM.md — our MCM surface diff
