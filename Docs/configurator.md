# Configurator Mode

Configurator Mode lets an admin edit the Hello IT menu tree on a Mac without hand-writing plist XML.

## Unlock

The **Configurator Mode…** menu item is hidden until you **⇧⌥-click** the Hello IT status item. After unlock it stays visible for that user (`configuratorModeUnlocked`).

Fleet can block unlock entirely (recommended on managed Macs — Apply writes the user `com.github.ygini.Hello-IT` domain until MDM refreshes):

```bash
defaults write com.github.ygini.Hello-IT disableConfiguratorMode -bool YES
```

Sample profile: `example/HelloIT-DisableConfigurator.mobileconfig`.

## Workflow

1. Unlock Configurator Mode
2. Edit the menu tree (add / duplicate / reorder / delete items)
3. **Apply & Reload** — writes prefs and rebuilds the live menu for a local preview
4. **Export** — plist, `.mobileconfig`, bash installer (`defaults import`), or **All three…** under one name

## Item types

Friendly Type names map to plugin `functionIdentifier` values, including:

| Type | Identifier |
|---|---|
| System info | `public.system.info` |
| Munki | `public.munki` |
| Send email | `public.send.email` |
| About | `public.about` |
| Script | `public.script.item` |
| Command | `public.command.item` |
| HTTP test | `public.http.status` |
| … | existing Hello IT plugins |

Stateful types support optional **Alerts** (thresholds where applicable) and **Notifications** (`notificationWhenStateTurn*`). Command items can optionally notify on completion.

See [built-in-plugins.md](built-in-plugins.md) for built-in settings keys.
