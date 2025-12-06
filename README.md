# Antigravity Switcher

A native macOS menu bar application to easily switch between **Antigravity** accounts.

## Features

- **Backup Accounts**: Save the current state of your Antigravity app (database) as a backup.
- **Switch Accounts**: Seamlessly switch between saved accounts. The Antigravity app stays open during the switch!
- **Manage Accounts**: Remove old or unused account backups directly from the menu.
- **Native Experience**: Runs quietly in your menu bar.

## Requirements

- macOS 13.0+
- Swift 5.9+

## Building

To build the application, run the provided build script:

```bash
./build.sh
```

The application will be built to: `build/AntigravityMenuBar.app`

## Installation

1. Build the app using the command above.
2. Drag `build/AntigravityMenuBar.app` to your `Applications` folder.
3. Launch the app. It will appear in your menu bar with a "person" icon.
