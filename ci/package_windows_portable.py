"""Create the self-contained portable Windows ZIP from release build outputs."""

import pathlib
import subprocess
import sys
import zipfile


REPO = pathlib.Path(__file__).resolve().parent.parent


def package(target_dir: pathlib.Path, archive: pathlib.Path) -> None:
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=REPO, text=True
    ).strip()
    files = {
        "wezterm.exe": target_dir / "release/wezterm.exe",
        "wezterm-gui.exe": target_dir / "release/wezterm-gui.exe",
        "wezterm-mux-server.exe": target_dir / "release/wezterm-mux-server.exe",
        "strip-ansi-escapes.exe": target_dir / "release/strip-ansi-escapes.exe",
        "wezterm.pdb": target_dir / "release/wezterm.pdb",
        "conpty.dll": REPO / "assets/windows/conhost/conpty.dll",
        "OpenConsole.exe": REPO / "assets/windows/conhost/OpenConsole.exe",
        "libEGL.dll": REPO / "assets/windows/angle/libEGL.dll",
        "libGLESv2.dll": REPO / "assets/windows/angle/libGLESv2.dll",
        "mesa/opengl32.dll": target_dir / "release/mesa/opengl32.dll",
        "LICENSE.md": REPO / "LICENSE.md",
        "LICENSE_OFL.txt": REPO / "assets/fonts/LICENSE_OFL.txt",
        "LICENSE_POWERLINE_EXTRA.txt": REPO / "assets/fonts/LICENSE_POWERLINE_EXTRA.txt",
        "THIRD_PARTY_NOTICES.md": REPO / "ci/THIRD_PARTY_NOTICES.md",
        "third-party/conhost/README.md": REPO / "assets/windows/conhost/README.md",
        "third-party/mesa/README.md": REPO / "assets/windows/mesa/README.md",
        "third-party/ANGLE-LICENSE.txt": REPO / "ci/licenses/ANGLE-LICENSE.txt",
        "third-party/MICROSOFT-TERMINAL-LICENSE.txt": REPO / "ci/licenses/MICROSOFT-TERMINAL-LICENSE.txt",
    }
    missing = [str(path) for path in files.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing package inputs: " + ", ".join(missing))
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as result:
        for name, path in files.items():
            result.write(path, name)
        result.writestr("SOURCE_REVISION", f"zackees/wezterm@{revision}\n")


if __name__ == "__main__":
    package(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
