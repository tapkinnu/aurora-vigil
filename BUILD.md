# Building Aurora Vigil — Desktop Release

Aurora Vigil is a Godot **4.4.1 (stable)** project that renders with the
`gl_compatibility` backend, so the exported game runs on a wide range of desktop
GPUs without requiring Vulkan.

## Prerequisites

1. **Godot 4.4.1 stable** (standard build, not .NET). This repo's tooling uses
   `/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64`; substitute your own
   path via the `GODOT` env var.
2. **Export templates for 4.4.1 stable.** These are *not* bundled with the engine and
   must be installed once. The export will fail with
   `No export template found at the expected path` until they are present.

   Install them either from the editor — **Editor ▸ Manage Export Templates ▸
   Download and Install** — or from the CLI:

   ```bash
   # Download the official templates archive for your exact engine version:
   #   https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz
   GODOT=/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64
   "$GODOT" --headless --install-export-templates /path/to/Godot_v4.4.1-stable_export_templates.tpz
   ```

   Templates install to `~/.local/share/godot/export_templates/4.4.1.stable/`.

## Export presets

`export_presets.cfg` (checked into the repo root) defines two presets:

| Preset            | Platform          | Output                                  |
| ----------------- | ----------------- | --------------------------------------- |
| `Windows Desktop` | Windows Desktop   | `build/windows/AuroraVigil.exe`         |
| `Linux/X11`       | Linux/X11         | `build/linux/AuroraVigil.x86_64`        |

Both exclude the dev-only `tools/`, `tests/`, `artifacts/`, and `.godot_validation/`
folders from the shipped pack.

## Building the Windows desktop `.exe`

From the project root, with templates installed:

```bash
GODOT=/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/AuroraVigil.exe
```

This produces a zip-ready folder:

```
build/windows/
├── AuroraVigil.exe        # the game
├── AuroraVigil.pck        # packed resources (unless embed_pck is enabled)
└── AuroraVigil.console.exe # console wrapper (debug/export_console_wrapper)
```

Zip the `build/windows/` directory to distribute. To embed the pack inside the
`.exe` (single-file distribution) set `binary_format/embed_pck=true` in the preset
options first.

For a quick local (Linux) build to smoke-test the packaging:

```bash
mkdir -p build/linux
"$GODOT" --headless --path . --export-release "Linux/X11" build/linux/AuroraVigil.x86_64
```

## Verifying before you ship

Run the studio QA harness — all gates must be green:

```bash
python3 tools/studio_harness.py
# report: /tmp/studio_harness/aurora-vigil/report.md
```

## Controls (shipped build)

- **Keyboard:** WASD fly · Space/Ctrl climb-dive · Shift boost · F/Q/E/R powers · Esc pause
- **Gamepad (Xbox layout):** Left stick fly · Triggers climb/dive · Bumpers boost ·
  A rescue / B sonic / X radiant / Y aegis · Right stick look · Select pause

Difficulty (Easy / Normal / Hard), volumes, look sensitivity, and invert-Y are set in
**Settings** (reachable from the main menu and the pause menu) and persist to
`user://settings.cfg`.

> **Note:** As of this commit the build machine has no 4.4.1 export templates
> installed (`~/.local/share/godot/export_templates/` is empty), so the binaries are
> not produced here. Install the templates per above and re-run the export command;
> `export_presets.cfg` is ready to use as-is.
