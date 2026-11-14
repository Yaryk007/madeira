# Madeira Glass

This branch (`glass`) is a fork of Madeira with a new home interface. Everything below
is on top of upstream's `main`.

- **Interface:** a console shell built to the design prototype
  (`docs/design/madeira-prototype.dc.html`): boot screen, "Who's playing?", Home, Library,
  Store and Settings, a quick menu, controller hints, and in a game the prototype's starting
  screen and left drawer menu. Sizes, spacing and motion follow the prototype exactly; its
  CSS spring and cubic-bezier curves are replayed by `GlassMotion` (`GlassOS.swift`,
  `GlassRoot.swift`, and the `LibraryHUD` extension at the end of `Library.swift`).
  Settings › Appearance › Glass interface returns to the classic library. The look before
  this rebuild is kept on the branch `glass-backup-2026-11-14` (tag
  `glass-before-prototype-2026-11-14`).
- **Stores:** shop on Steam, Epic Games and GOG once signed in (`GlassStore.swift`).
  Payment happens on the store's own site. Epic has no open catalogue, so its tab shows
  the current free games and opens the store site for everything else.
- **Import:** folders, programs, `.zip`, `.rar` and `.7z` (`GlassImport.swift`,
  `GlassArchive.swift`). See the top of `GlassArchive.swift` for how space is saved.
- **Controller:** full navigation, PlayStation or Xbox icons, a test page for buttons,
  rumble and adaptive triggers (`GlassController.swift`). Pages from the classic
  interface are reached with a stick-driven pointer and a pad keyboard.
- **Memory:** upstream's donor pool (BCD's memory pool) is on by default, sized by device
  (`GlassMemory`, Settings › Performance, or the quick menu).
