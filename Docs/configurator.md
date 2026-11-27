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
4. **Export** — plist, `.mobileconfig`, bash installer, or **All three…** under one name

The bash export works as a normal user, under `sudo`, or as an MDM/Munki script: root installs computer prefs and clears per-user overrides; reload goes through the LaunchAgent (never `open` as root). For continuous MDM management of the domain, prefer **Export → Mobileconfig…**.

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
| HTTP test | `public.test.http` |
| … | existing Hello IT plugins |

Stateful types support optional **Alerts** (thresholds where applicable) and **Notifications** (`notificationWhenStateTurn*`). Command items can optionally notify on completion. Script items can opt into **Run on network change** (`settings.network`).

Imported plugins that are not in the built-in Type list stay editable for title, icon, alerts, and repeat; other keys are left as imported.

See [built-in-plugins.md](built-in-plugins.md) for built-in settings keys.
