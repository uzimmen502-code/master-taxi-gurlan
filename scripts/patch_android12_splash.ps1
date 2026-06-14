# flutter_native_splash:create dan KEYIN.
# Android 12+: poster faqat windowBackground + Flutter SplashScreenDrawable (icon slot emas!).
$v31 = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
</resources>
"@

$v31Night = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
</resources>
"@

$root = Split-Path -Parent $PSScriptRoot
Set-Content -Path (Join-Path $root "android\app\src\main\res\values-v31\styles.xml") -Value $v31 -Encoding UTF8
Set-Content -Path (Join-Path $root "android\app\src\main\res\values-night-v31\styles.xml") -Value $v31Night -Encoding UTF8

$nodpi = Join-Path $root "android\app\src\main\res\drawable-nodpi"
New-Item -ItemType Directory -Path $nodpi -Force | Out-Null
Copy-Item -Path (Join-Path $root "assets\images\splash_full.png") -Destination (Join-Path $nodpi "background.png") -Force
Copy-Item -Path (Join-Path $root "assets\images\splash_full.png") -Destination (Join-Path $root "android\app\src\main\res\drawable\background.png") -Force

Write-Host "Patched v31: full-screen launch_background only (no icon-slot poster)."
