# Native app icon

`AppIcon.icon` is an Icon Composer document compiled by Xcode `actool` into `Assets.car` and legacy `AppIcon.icns`. `CFBundleIconName=AppIcon` selects the native rendition on current macOS.

The raster artwork is an exact copy of `better-remote-3d-v4.png`; no devices or source pixels were regenerated. A native opaque deep teal background fills the icon canvas. The artwork is placed at scale 0.94 with zero translation, retaining its existing composition while fitting the native masked silhouette. Foreground glass is disabled and group shadow opacity is zero. Masking and perimeter highlights are supplied by the system.

The old ICNS-only export contained transparent padding and a pre-rounded tile. On current macOS the icon appeared reduced inside a grey compatibility enclosure. The native document removes that nested enclosure; Finder's selection highlight and the system's normal icon margins remain separate from the artwork.

Build validation must check both `Assets.car` and `AppIcon.icns` in the mounted DMG. Rendering the mounted application through `NSWorkspace.icon(forFile:)` verifies the system-selected icon, rather than only the source PNG.
