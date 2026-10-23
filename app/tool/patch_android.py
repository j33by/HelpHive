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

for perm in ('SYSTEM_ALERT_WINDOW', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_SPECIAL_USE', 'WAKE_LOCK',
             'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS', 'RECEIVE_BOOT_COMPLETED'):
    if f'android.permission.{perm}' not in xml:
        xml = xml.replace('<application', f'<uses-permission android:name="android.permission.{perm}"/>\n    <application', 1)

# xmlns:tools is needed to override the background service's declaration
if 'xmlns:tools' not in xml:
    xml = xml.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

if 'BubbleService' not in xml:
    services = '''
        <!-- the floating chat bubble over other apps -->
        <service android:name=".BubbleService" android:exported="false"/>
        <!-- the quiet background listener; "specialUse" has no daily time limit -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:exported="true"
            android:foregroundServiceType="specialUse"
            tools:replace="android:foregroundServiceType,android:exported">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Listens for new chat messages and alerts while the app is closed"/>
        </service>
    '''
    xml = xml.replace('</application>', services + '</application>', 1)

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
    ('close.png', 'ic_bubble_close.png'),
    ('back.png', 'ic_panel_back.png'),      # chat window: back to the chat list
    ('send_fill.png', 'ic_panel_send.png'),  # chat window: send button
    ('bell_fill.png', 'ic_bg_service_small.png'),  # icon of the quiet listener notification
):
    shutil.copyfile(os.path.join(icons, src_name), os.path.join(drawable, res_name))
# the two notification tones, used by the notification channels
raw_dir = os.path.join(root, 'src', 'main', 'res', 'raw')
os.makedirs(raw_dir, exist_ok=True)
sounds = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'sounds')
shutil.copyfile(os.path.join(sounds, 'message.wav'), os.path.join(raw_dir, 'message_tone.wav'))
shutil.copyfile(os.path.join(sounds, 'alert.wav'), os.path.join(raw_dir, 'alert_tone.wav'))

# native code for the floating bubble, written into the app's own package
kotlin_root = os.path.join(root, 'src', 'main', 'kotlin')
activity = None
for dirpath, _, files in os.walk(kotlin_root):
    if 'MainActivity.kt' in files:
        activity = os.path.join(dirpath, 'MainActivity.kt')
        break
if activity is None:
    sys.exit('MainActivity.kt not found under ' + kotlin_root)
pkg = re.search(r'^package\s+([\w.]+)', open(activity, encoding='utf-8').read(), re.M).group(1)
tmpl = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'android')
for name in ('MainActivity', 'BubbleService'):
    code = open(os.path.join(tmpl, name + '.kt.tmpl'), encoding='utf-8').read().replace('__PKG__', pkg)
    open(os.path.join(os.path.dirname(activity), name + '.kt'), 'w', encoding='utf-8').write(code)
print('Bubble service written to package', pkg)

# icons are looked up by name at runtime, so keep the resource shrinker away from them
raw = os.path.join(root, 'src', 'main', 'res', 'raw')
os.makedirs(raw, exist_ok=True)
with open(os.path.join(raw, 'keep.xml'), 'w', encoding='utf-8') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_*,@raw/*_tone"/>\n')
print('Notification icons copied.')

print('Android project patched.')
