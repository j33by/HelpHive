#!/usr/bin/env python3
"""Run once after `flutter create --platforms=android .` (Codemagic does this for you).

Sets the app label, the internet permission, the Google sign-in deep link,
turns off cleartext traffic and backups, and raises minSdk to 23 (needed by
the secure session store).
"""
import glob
import os
import re
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'android', 'app')
manifest = os.path.join(root, 'src', 'main', 'AndroidManifest.xml')
if not os.path.exists(manifest):
    sys.exit('android/ not found. Run: flutter create --platforms=android --org io.helphive --project-name helphive .')

xml = open(manifest, encoding='utf-8').read()

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

print('Android project patched.')
