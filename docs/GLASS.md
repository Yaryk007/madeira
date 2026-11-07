# Madeira Glass

This branch (`glass`) is a fork of Madeira with a new home interface. Everything below
is on top of upstream's `main`.

- **Interface:** Home, Library, Store and Settings in Liquid Glass, landscape only
  (`GlassRoot.swift`). Settings › Interface returns to the classic library.
- **Stores:** shop on Steam, Epic Games and GOG once signed in (`GlassStore.swift`).
  Payment happens on the store's own site. Epic has no open catalogue, so its tab shows
  the current free games and opens the store site for everything else.
- **Import:** folders, programs, `.zip`, `.rar` and `.7z` (`GlassImport.swift`,
  `GlassArchive.swift`). See the top of `GlassArchive.swift` for how space is saved.
- **Controller:** full navigation, PlayStation or Xbox icons, a test page for buttons,
  rumble and adaptive triggers (`GlassController.swift`). Pages from the classic
  interface are reached with a stick-driven pointer and a pad keyboard.
- **Memory:** upstream's donor pool (BCD's memory pool) is on by default, sized by device
  (`GlassMemory`, Settings › Memory).
