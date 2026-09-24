# Third-party components in the Windows portable package

The bundled `conpty.dll` and `OpenConsole.exe` come from Microsoft Terminal,
which is published under the MIT license. Its license text is included as
`third-party/MICROSOFT-TERMINAL-LICENSE.txt`. See also
https://github.com/microsoft/terminal/blob/main/LICENSE and the accompanying
`assets/windows/conhost/README.md` in the source tree.

The bundled `libEGL.dll` and `libGLESv2.dll` are ANGLE components. ANGLE's
license text is included as `third-party/ANGLE-LICENSE.txt`. Additional
third-party notices are maintained at
https://chromium.googlesource.com/angle/angle/+/main/LICENSE and
https://chromium.googlesource.com/angle/angle/+/main/third_party/.

The bundled `mesa/opengl32.dll` is Mesa. Its license information is at
https://docs.mesa3d.org/license.html; the source tree also includes
`assets/windows/mesa/README.md` describing this binary's provenance.

Bundled fonts are described in `LICENSE.md`. Their OFL license text is
included as `LICENSE_OFL.txt`; additional Powerline font terms are included
as `LICENSE_POWERLINE_EXTRA.txt`.
