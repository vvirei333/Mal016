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

## Session-1 late addendum (same day)
- Native 46349938 has versions 78-81 but ONLY v81 has contents/ (others empty).
  Swapping contents in ALL versions did NOT change the gallery tile art.
- Purged MappedImageCache/Wallpaper + WallpaperColorBoxesCache + GalleryCache —
  no effect on tile rendering. Tile thumbnails are NOT rendered live from
  contents/ on 16.7.16.
- Distinctive file: native contents contain
  `com.apple.posterkit.provider.contents.galleryOptions`; packs ship
  `...otherMetadata.plist` instead. Candidate gate.
- Device RESTORED to pristine state (4 native descriptors verified, caches
  cleared, ProviderInfo original). SuperMarioBros_fixed.tendies (productTypes
  patched) remains in Media + PC /tmp/mal0push/.
- Next session top probes: (1) diff native vs pack Wallpaper.plist +
  galleryOptions vs otherMetadata semantics (pull both, plistlib);
  (2) grep PaperBoard/WallpaperKit binaries in dyld cache for
  galleryOptions/ATXFaceGallery keys; (3) idevicesyslog during gallery open
  filtered 'ATX|PaperBoard|snapshot|thumbnail'; (4) check whether tile art
  comes from Duet faceGallery preview assets, not the store.

## Session-1 final addendum (post-mortem of probes)
- Native per-descriptor `com.apple.posterkit.provider.contents.galleryOptions`
  = ATXPosterDescriptorGalleryOptions (localizedTitle 'Коллекции', hero flag,
  complications flags). Packs carry `otherMetadata` instead → cloned native
  galleryOptions with custom title for Mario — still no tile.
- Duet stream `/var/mobile/Library/DuetExpertCenter/streams/faceGallery/local/
  815610501801543` (8MB binary, device-scoped header, contains 7400.DYNAMIC ×40
  and native instance UUIDs ×3) — patched equal-length (B18666BC→5D800000 ×3) —
  still no tile. Rolled back.
- syslog during gallery open: NO CollectionsPoster process spawn at all; only
  PhotosPosterProvider XPC. The gallery UI never touches foreign descriptors.
- **Conclusion:** tile art/rows are provisioned through a channel that only
  accepts descriptors registered in a trust store not yet located. Top
  hypothesis: MobileAsset asset audit (com.apple.mobileassetd) or a PosterKit
  SQLite/plist index inside SpringBoard container.
- **Next session = binary RE (ABrake27 home turf):** extract
  WallpaperKit/WallpaperFoundation/PaperBoard + PosterKit-related dylibs from
  16.7.16 dyld cache (extracted_16716/ available, 479MB), grep for
  ATXFaceGalleryItem/descriptorIdentifier/galleryOptions resolution, find the
  trust check that gates foreign descriptors. Diff against 17.x would also
  reveal what Nugget exploits.
- Device state: fully pristine (Duet restored, descriptors removed, caches
  purged). PC artifacts: /tmp/rsn/* (native galleryOptions/userInfo/Duet
  backup), /tmp/pbpull/*, /tmp/mal0push/* scripts.
