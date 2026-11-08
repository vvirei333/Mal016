# Mal016 — PosterBoard/MobileGestalt CLI for jailbroken iOS 16.x 

Jailbreak utility (Dopamine/root) — **no exploits**. Mal016 uses the root
access you already have to do what exploit tools (BQEscape/3105) do through
bugs. Target: iPhone 8+ (A11), iOS 16.7.16.

## Why a separate tool
- Research value: nobody tested PosterBoard 16.x vs 17+ `.tendies` packs.
  Mal016 logs exactly which descriptor fields 16.x accepts/rejects.

## Commands (v0.1 plan)
    Mal016 recon                 # identity + paths (RECON-first!)
    Mal016 gestalt dump|get K|set K V|rm K
    Mal016 gestalt backup|restore
    Mal016 tendie inspect X.tendies
    Mal016 tendie import X.tendies [--reset]

## Log
Documents/Mal016.log; header always: hw.machine + kern.osrelease
(lesson from the newjail runs: logs without identity are unattributable).

## Build
Linux cross-compile, same pipeline as ABrake27 ASTCProbe (clang → ld64.lld
→ ldid). See build_mal016.sh.

## References
- SerStars/Nugget-Wallpapers — open .tendies catalog (111+ packs)
- leminlimez/CowabungaLite — partial-restore architecture (iOS 15+, no tendies)
- YangJiiii/3105 — PosterBoard lab on 17+ (Geod-MCM), feature reference
- ABrake27 research/intel/mcm/BQ272_MCM.md — our MCM surface diff
