# flutter_native_splash:create dan KEYIN.
# Android 12+: faqat qora fon + bo'sh icon (animatsiya Flutter'da).
$v31 = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowSplashScreenBackground">@color/splash_black</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon_empty</item>
        <item name="android:windowSplashScreenIconBackgroundColor">@color/splash_black</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@color/splash_black</item>
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
        <item name="android:windowSplashScreenBackground">@color/splash_black</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon_empty</item>
        <item name="android:windowSplashScreenIconBackgroundColor">@color/splash_black</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/splash_black</item>
    </style>
</resources>
"@

$launchBg = @"
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/splash_black"/>
</layer-list>
"@

$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root "android\app\src\main\res"
Set-Content -Path (Join-Path $res "values-v31\styles.xml") -Value $v31 -Encoding UTF8
Set-Content -Path (Join-Path $res "values-night-v31\styles.xml") -Value $v31Night -Encoding UTF8
Set-Content -Path (Join-Path $res "drawable\launch_background.xml") -Value $launchBg -Encoding UTF8
Set-Content -Path (Join-Path $res "drawable-v21\launch_background.xml") -Value $launchBg -Encoding UTF8

Write-Host "Patched: black native splash + empty Android 12 icon (Flutter animates logo)."
