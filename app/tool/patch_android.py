#!/usr/bin/env python3
"""Run once after `flutter create --platforms=android .` (Codemagic does this for you).

Sets the app label, the internet permission, the Google sign-in deep link,
turns off cleartext traffic and backups, and raises minSdk to 23 (needed by
the secure session store).

Also does the native side of system notifications (flutter_local_notifications):
the POST_NOTIFICATIONS permission, core library desugaring, the drawables the
notifications refer to by name, and a keep rule so release builds don't strip
them.
"""
import glob
import os
import re
import shutil
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'android', 'app')
manifest = os.path.join(root, 'src', 'main', 'AndroidManifest.xml')
if not os.path.exists(manifest):
    sys.exit('android/ not found. Run: flutter create --platforms=android --org io.helphive --project-name helphive .')

xml = open(manifest, encoding='utf-8').read()

if 'android.permission.POST_NOTIFICATIONS' not in xml:
    xml = xml.replace('<application', '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application', 1)

if 'android.permission.INTERNET' not in xml:
    xml = xml.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

xml = re.sub(r'android:label="[^"]*"', 'android:label="HelpHive"', xml, count=1)
for attr, val in (('allowBackup', 'false'), ('usesCleartextTraffic', 'false')):
    if f'android:{attr}=' not in xml:
        xml = xml.replace('<application', f'<application\n        android:{attr}="{val}"', 1)

link = '''<intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="io.helphive.app" android:host="login-callback"/>
            </intent-filter>
            '''
if 'login-callback' not in xml:
    # drop it just before the closing tag of the main activity
    idx = xml.index('</activity>')
    xml = xml[:idx] + '    ' + link + xml[idx:]

open(manifest, 'w', encoding='utf-8').write(xml)

for gradle in glob.glob(os.path.join(root, 'build.gradle*')):
    src = open(gradle, encoding='utf-8').read()
    new = re.sub(r'minSdk(Version)?(\s*=\s*|\s+)flutter\.minSdkVersion',
                 lambda m: f'minSdk{m.group(1) or ""}{m.group(2)}23', src)
    if new != src:
        open(gradle, 'w', encoding='utf-8').write(new)
        print('minSdk ->', os.path.basename(gradle))


# --- core library desugaring (required by flutter_local_notifications)
DESUGAR = 'com.android.tools:desugar_jdk_libs:2.1.4'
for gradle in glob.glob(os.path.join(root, 'build.gradle*')):
    src = open(gradle, encoding='utf-8').read()
    new = src
    kts = gradle.endswith('.kts')
    if 'oreLibraryDesugaring' not in new:
        flag = 'isCoreLibraryDesugaringEnabled = true' if kts else 'coreLibraryDesugaringEnabled true'
        new, n = re.subn(r'(compileOptions\s*\{)', lambda m: m.group(1) + '\n        ' + flag, new, count=1)
        if n == 0:
            sys.exit('Could not find compileOptions in ' + gradle)
        dep = f'\n\ndependencies {{\n    coreLibraryDesugaring("{DESUGAR}")\n}}\n' if kts else f"\n\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR}'\n}}\n"
        new = new.rstrip('\n') + dep
    if new != src:
        open(gradle, 'w', encoding='utf-8').write(new)
        print('desugaring ->', os.path.basename(gradle))

# --- drawables the notifications look up by name
res = os.path.join(root, 'src', 'main', 'res')
icons = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'icons')
drawables = {
    'ic_stat_chat': 'chat.png',      # status-bar icons only use the alpha channel
    'ic_stat_bell': 'bell.png',
    'ic_action_like': 'heart.png',
    'ic_action_reply': 'reply.png',
    'ic_large_bee': 'bee.png',       # fallback avatar
}
os.makedirs(os.path.join(res, 'drawable-nodpi'), exist_ok=True)
for name, src_png in drawables.items():
    shutil.copyfile(os.path.join(icons, src_png), os.path.join(res, 'drawable-nodpi', name + '.png'))

# resources only referenced by string would be stripped from release builds
os.makedirs(os.path.join(res, 'raw'), exist_ok=True)
with open(os.path.join(res, 'raw', 'keep.xml'), 'w', encoding='utf-8') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources xmlns:tools="http://schemas.android.com/tools"\n'
            '    tools:keep="@drawable/ic_stat_*,@drawable/ic_action_*,@drawable/ic_large_bee" />\n')

print('Android project patched.')
