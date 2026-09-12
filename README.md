# ROG control

An [Omarchy](https://omarchy.org/) bar panel for ASUS ROG and TUF laptops. Temperatures, fan speeds, power profile, battery charge limit and keyboard backlight — in one panel, with no password prompts.

![The ROG control panel](screenshots/panel.png)

## What it does

The ROG wordmark sits in your bar. Clicking it opens the panel and changes nothing on its own — there is no click-to-cycle guesswork.

**Live sensors.** CPU, integrated GPU and discrete GPU temperatures, both fan speeds, and battery state. The discrete GPU is only queried when it is already awake, so opening the panel never wakes a sleeping dGPU just to report on it.

**Power profile.** Silent / Balanced / Turbo, through `power-profiles-daemon`. The panel labels them the way the laptop is badged but sets the profile the way the rest of Omarchy does, so the bar's own power widget stays in agreement. The raw ASUS thermal mode is shown underneath.

**Battery charge limit.** 60% / 80% / 100%, written to the standard `charge_control_end_threshold` sysfs attribute. Capping at 80% meaningfully extends the life of a laptop that mostly lives on AC.

**Keyboard backlight.** Off / Low / Medium / High. A dropdown rather than a slider — four discrete hardware levels are fiddly to land on with a slider. The physical `Fn`+`Up` / `Fn`+`Down` keys keep working as normal.

## Nothing is hardcoded

This started as a config for one G14 and was generalised, so it should come up correctly on other ROG and TUF machines:

- Model, CPU and discrete GPU names come from DMI and the PCI modalias. The GPU name is resolved by parsing `pci.ids`, which is pure string handling — it never touches PCI config space, so a suspended dGPU stays suspended.
- Every hwmon, LED and PCI device is resolved **by name or driver at call time**, never by index. `hwmon4` today can be `hwmon6` after a kernel update, and a panel that hardcodes the number silently goes blank.
- Each section is gated on the sysfs attribute actually existing. No charge-limit support means no BATTERY section, rather than a dead control.

## Install

```bash
git clone https://github.com/<you>/omarchy-rog-control \
  ~/.config/omarchy/plugins/armnt.rog-control
omarchy restart shell
```

Then add it to your bar — via `omarchy bar`, or by adding `{ "id": "armnt.rog-control" }` to the `right` section of `~/.config/omarchy/shell.json`.

### Optional: passwordless charge limit

Writing the charge limit needs root. Out of the box the panel asks through polkit. To make it passwordless, run the bundled setup once:

```bash
sudo bash ~/.config/omarchy/plugins/armnt.rog-control/install/enable-passwordless-charge-limit.sh
```

That installs a small helper that accepts **only** the fixed set of levels the panel offers, plus a `sudoers` rule granting `NOPASSWD` for exactly that one command. Nothing else is widened. The script verifies the result and fails loudly if the rule did not take.

The power profile and keyboard backlight never need root — they go through `power-profiles-daemon` and `brightnessctl` respectively.

## How it is put together

```
RogControl.qml    the panel: an Omarchy Panel + KeyboardPanel with Dropdowns
RogMark.qml       the ROG wordmark, drawn as vector paths
bin/rog-status    reads all hardware state, emits key<TAB>value lines
bin/rog-set       applies one setting; the only place privilege is handled
install/          one-time passwordless setup for the charge limit
```

Every read goes through `bin/rog-status` and every write through `bin/rog-set`, both resolved relative to the QML file so the plugin is self-contained and needs nothing on `$PATH`. Both are plain shell and can be run directly, which makes the panel easy to debug:

```bash
~/.config/omarchy/plugins/armnt.rog-control/bin/rog-status
```

The wordmark is drawn with `QtQuick.Shapes` rather than shipped as an image or borrowed from a Nerd Font, following the same pattern Omarchy uses for its own brand marks: it tints with your theme, stays sharp at any bar size, and there is no asset to go missing.

## Requirements

Omarchy 4.0+, `power-profiles-daemon`, `brightnessctl`. All are already present on a standard Omarchy install.

## Licence

MIT.
