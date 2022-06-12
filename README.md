# SwaySettings

A GUI for configuring your sway desktop

## Features

- Set and remove auto start apps
- Change default apps
- Change GTK theme settings (GTK theme is set per GTK4 color-scheme, ie dark and light mode)
- Mouse and trackpad settings
- Keyboard layout settings
- Switch Wallpaper (selected wallpaper will be located at .cache/wallpaper)
- Configure 
[Sway Notification Center](https://github.com/ErikReider/SwayNotificationCenter)
- sway-wallpaper (a swaybg replacement) which includes a slick fade transition 😎

## Install

### Arch

The package is available on the 
[AUR](https://aur.archlinux.org/packages/swaysettings-git/) \
Or:

``` zsh
makepkg -si
```

### Other Distros

``` zsh
meson build
ninja -C build
meson install -C build
```

Add these lines to the end of your main sway config file

``` ini
# Applies all generated settings
include ~/.config/sway/.generated_settings/*.conf

# Launches sway-wallpaper when setting wallpaper from swaymsg.
# Without this, swaybg would launch instead...
swaybg_command sway-wallpaper

# To apply the selected wallpaper
exec_always swaymsg "output * bg ~/.cache/wallpaper fill"

# Start all of the non-hidden applications in ~/.config/autostart
# This executable is included in the swaysettings package
exec sway-autostart
```
