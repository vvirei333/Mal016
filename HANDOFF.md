# Mal016 HANDOFF — PosterBoard tendies on iOS 16.7.16 (for next AI session)

## Context
Goal: make community `.tendies` wallpaper packs work on iPhone 8+ (iPhone10,5),
iOS 16.7.16 (20H392), jailbroken (Dopamine, root). Owner: Ivan. Tooling: Mal016
CLI (this repo, cross-compiled on Linux, deployed at /var/jb/usr/bin/Mal016).
SSH: USB + `iproxy 2222 22` → root@localhost -p 2222, password: thor.
Helper scripts on PC: /tmp/ssh_ip.py (run cmd via ssh), /tmp/mal0push/*.
Packs: Mal016/packs/ + fetch_packs.sh (SerStars/Nugget-Wallpapers catalog).

## Established facts (see docs/POSTERBOARD_16_RESEARCH.md)
- Store: .../PRBPosterExtensionDataStore/59/Extensions/<provider>/descriptors/
- Target provider: com.apple.WallpaperKit.CollectionsPoster (Коллекции, 7400.*)
- Pack normalization needed: productTypes→['iPhone10,5'], 390w-844h→414w-736h
  (outer .wallpaper dir AND inner *.ca dirs), UUID→valid hex.
- Gallery = ATXFaceGalleryConfiguration (Duet stream faceGallery, cached in
  GalleryCache/*.plist); items keyed '<identifier-file>.DYNAMIC' + provider.
- ProviderInfo.plist kProactiveDynamicPosterDescriptorOrdering = registration
  list (patchable via python plistlib, NSKeyedArchiver, UID append).

## Blocked at
Descriptors placed + registered did not appear in gallery; content-swap into
native 7400 v81 contents did not re-render either. Suspects (in order):
1. **RuntimeSnapshotMetadata-lock/home.plist** in descriptor versions/<N>/ —
   likely pre-rendered snapshot refs the system trusts instead of contents.
2. SpringBoard/posterboard snapshot caches outside the store.
3. ATX gallery provisioning only trusts MobileAsset-delivered descriptors.

## Next probes
- Pull RuntimeSnapshotMetadata-*.plist from native 7400 descriptor
  (46349938-3F6F-4333-9329-7A10BDA4AFDE/versions/78..81) and from a pack;
  diff structure (they are binary plists).
- idevicesyslog filtered 'WallpaperKit|PosterKit|snapshot|PaperBoard' while
  opening gallery.
- Check /var/mobile/Library/Caches/... PosterBoard/SpringBoard poster caches.
- Alternative path: PaperBoard.LegacyPoster (older engine) — its descriptors
  dir is empty; maybe 16.x still instantiates LegacyPoster for custom CA.
- Rollback: native 46349938 backup at device /var/tmp/backup_4634; original
  ProviderInfo in PC /tmp/pbpull/wk_provider.plist.

## Hygiene rules (from project scope)
Static analysis and device- owner experiments only; no exploit development;
revert device state after experiments; logs must carry RECON identity.
