# Contributing to WinTool

Thanks for helping. WinTool should stay easy to read and careful about what it changes on someone's PC.

## Setup

1. Fork [Hinrikao/WinTool](https://github.com/Hinrikao/WinTool) and clone your fork.
2. Install PowerShell 7 if you are not already on Windows PowerShell 5.1. The scripts target Windows PowerShell 5.1, so avoid syntax that only exists in PowerShell 7.
3. Run the checks:

```powershell
./build/Invoke-CI.ps1
```

On Windows you can also open the window from source:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\src\Start-WinTool.ps1
```

## Where to change things

- App list: `data/apps.json`
- Tweaks and presets: `data/tweaks.json`
- Terminal packages and fonts: `data/terminal.json`
- Graphics vendor links: `data/updates.json`
- Window layout: `assets/MainWindow.xaml`
- Behavior: `src/Private/` and `src/UI/`
- The file order inside the launcher: `build/files.txt`

Do not hand-edit `wintool.ps1`. After a source or data change, run `./build/Build-WinTool.ps1` and commit the new launcher with the change.

## Pull requests

- Keep the UI and docs in English.
- Describe a tweak honestly, including what undo does and anything it cannot restore.
- New tweak actions have to be a known type in `data/tweaks.json`. Do not teach the catalog to run arbitrary script.
- Prefer official winget package ids and official vendor download pages.
- Run `./build/Invoke-CI.ps1` before you open the pull request. CI runs that same script.

## License

By contributing, you agree that your changes are licensed under the MIT license in [LICENSE](LICENSE), copyright Henrique.
