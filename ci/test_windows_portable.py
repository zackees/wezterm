"""Smoke test the portable Windows package without compiling Windows binaries."""

import pathlib
import subprocess
import tempfile
import zipfile


REPO = pathlib.Path(__file__).resolve().parent.parent


def test_package():
    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        release = root / "target" / "release"
        (release / "mesa").mkdir(parents=True)
        for name in (
            "wezterm.exe",
            "wezterm-gui.exe",
            "wezterm-mux-server.exe",
            "strip-ansi-escapes.exe",
            "wezterm.pdb",
        ):
            (release / name).write_bytes(b"fixture")
        (release / "mesa" / "opengl32.dll").write_bytes(b"fixture")
        archive = root / "portable.zip"
        subprocess.run(
            ["python", "ci/package_windows_portable.py", str(root / "target"), str(archive)],
            cwd=REPO,
            check=True,
        )
        with zipfile.ZipFile(archive) as package:
            names = set(package.namelist())
            for name in (
                "wezterm.exe", "wezterm-gui.exe", "wezterm-mux-server.exe",
                "strip-ansi-escapes.exe", "conpty.dll", "OpenConsole.exe",
                "libEGL.dll", "libGLESv2.dll", "mesa/opengl32.dll",
                "SOURCE_REVISION", "LICENSE.md", "LICENSE_OFL.txt",
                "LICENSE_POWERLINE_EXTRA.txt", "THIRD_PARTY_NOTICES.md",
                "third-party/conhost/README.md", "third-party/mesa/README.md",
                "third-party/ANGLE-LICENSE.txt",
                "third-party/MICROSOFT-TERMINAL-LICENSE.txt",
            ):
                assert name in names, name
            revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
            assert package.read("SOURCE_REVISION").decode().strip() == f"zackees/wezterm@{revision}"
            notices = package.read("THIRD_PARTY_NOTICES.md").decode()
            assert all(name in notices for name in ("Microsoft Terminal", "Mesa", "ANGLE"))


if __name__ == "__main__":
    test_package()
