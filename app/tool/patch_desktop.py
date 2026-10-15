#!/usr/bin/env python3
"""Run once after `flutter create --platforms=windows,macos,linux .`
(the GitHub workflow does this for you).

Nothing here needs a signing key or a developer account.

  macOS    network + file-picker entitlements, otherwise the sandbox blocks
           every request, and the app is named HelpHive
  Windows  window title and a phone-friendly starting size
  Linux    window title and a phone-friendly starting size

Usage:  python3 tool/patch_desktop.py            (patches whatever exists)
        python3 tool/patch_desktop.py macos linux
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def path(*p):
    return os.path.join(ROOT, *p)


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def write(p, s):
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s)


def patch_macos():
    d = path('macos', 'Runner')
    if not os.path.isdir(d):
        return False
    keys = [
        'com.apple.security.network.client',        # talk to Supabase and the API
        'com.apple.security.network.server',        # loopback page for Google sign-in
        'com.apple.security.files.user-selected.read-only',  # choose a picture
    ]
    for name in ('DebugProfile.entitlements', 'Release.entitlements'):
        p = os.path.join(d, name)
        if not os.path.exists(p):
            continue
        xml = read(p)
        add = ''.join(f'\t<key>{k}</key>\n\t<true/>\n' for k in keys if k not in xml)
        if add:
            xml = xml.replace('</dict>', add + '</dict>', 1)
            write(p, xml)
    info = path('macos', 'Runner', 'Configs', 'AppInfo.xcconfig')
    if os.path.exists(info):
        write(info, re.sub(r'^PRODUCT_NAME\s*=.*$', 'PRODUCT_NAME = HelpHive', read(info), flags=re.M))
    return True


def patch_windows():
    p = path('windows', 'runner', 'main.cpp')
    if not os.path.exists(p):
        return False
    s = read(p)
    s = re.sub(r'CreateAndShow\(L"[^"]*"', 'CreateAndShow(L"HelpHive"', s)
    s = re.sub(r'Win32Window::Size size\(\s*\d+\s*,\s*\d+\s*\)', 'Win32Window::Size size(520, 860)', s)
    write(p, s)
    return True


def patch_linux():
    p = path('linux', 'runner', 'my_application.cc')
    if not os.path.exists(p):
        return False
    s = read(p)
    s = re.sub(r'(gtk_header_bar_set_title\(header_bar,\s*)"[^"]*"', r'\1"HelpHive"', s)
    s = re.sub(r'(gtk_window_set_title\(window,\s*)"[^"]*"', r'\1"HelpHive"', s)
    s = re.sub(r'gtk_window_set_default_size\(window,\s*\d+,\s*\d+\)', 'gtk_window_set_default_size(window, 520, 860)', s)
    write(p, s)
    return True


PATCHES = {'macos': patch_macos, 'windows': patch_windows, 'linux': patch_linux}

if __name__ == '__main__':
    wanted = sys.argv[1:] or list(PATCHES)
    done = [n for n in wanted if n in PATCHES and PATCHES[n]()]
    if not done:
        sys.exit('No desktop folders found. Run: flutter create --platforms=windows,macos,linux --org io.helphive --project-name helphive .')
    print('Patched:', ', '.join(done))
