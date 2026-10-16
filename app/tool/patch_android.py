#!/usr/bin/env python3
"""Run once after `flutter create --platforms=android .` (Codemagic does this for you).

Sets the app label, the internet permission, the Google sign-in deep link,
turns off cleartext traffic and backups, and raises minSdk to 23 (needed by
the secure session store).

Also sets up phone notifications: the POST_NOTIFICATIONS permission, core library
desugaring (needed by flutter_local_notifications) and the notification icons,
copied from assets/icons into the app's drawable resources.
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

if 'android.permission.INTERNET' not in xml:
    xml = xml.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

if 'android.permission.POST_NOTIFICATIONS' not in xml:
    xml = xml.replace('<application', '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application', 1)
if 'android.permission.VIBRATE' not in xml:
    xml = xml.replace('<application', '<uses-permission android:name="android.permission.VIBRATE"/>\n    <application', 1)

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

    # core library desugaring, required by flutter_local_notifications
    kts = gradle.endswith('.kts')
    src = open(gradle, encoding='utf-8').read()
    if True:
        if 'coreLibraryDesugaring' not in src and 'compileOptions' in src:
            flag = 'isCoreLibraryDesugaringEnabled = true' if kts else 'coreLibraryDesugaringEnabled true'
            src = re.sub(r'compileOptions\s*\{', lambda m: m.group(0) + '\n        ' + flag, src, count=1)
            dep = ('\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' if kts
                   else "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n")
            src += dep
            open(gradle, 'w', encoding='utf-8').write(src)
            print('desugaring ->', os.path.basename(gradle))

# notification icons: the status bar uses only the alpha channel, so the brown
# artwork becomes a clean white glyph; the large icon is the bee
icons = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'icons')
drawable = os.path.join(root, 'src', 'main', 'res', 'drawable')
os.makedirs(drawable, exist_ok=True)
for src_name, res_name in (
    ('chat_fill.png', 'ic_stat_chat.png'),
    ('bell_fill.png', 'ic_stat_bell.png'),
    ('heart_fill.png', 'ic_action_like.png'),
    ('reply.png', 'ic_action_reply.png'),
    ('bee.png', 'ic_large_bee.png'),
):
    shutil.copyfile(os.path.join(icons, src_name), os.path.join(drawable, res_name))
# icons are looked up by name at runtime, so keep the resource shrinker away from them
raw = os.path.join(root, 'src', 'main', 'res', 'raw')
os.makedirs(raw, exist_ok=True)
with open(os.path.join(raw, 'keep.xml'), 'w', encoding='utf-8') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_*"/>\n')
print('Notification icons copied.')

print('Android project patched.')
