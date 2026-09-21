# Flutter engine klasslarini butunlay saqlash SHART EMAS — flutter-gradle
# plugin o'zining consumer-rules.pro fayli orqali JNI ko'prigi uchun
# kerakli narsani avtomatik qo'shadi, pastdagi native-metod qoidasi esa
# buni yana mustahkamlaydi. `io.flutter.**`ni to'liq saqlash R8'ning
# shrink/obfuscate foizini sun'iy pasaytirar edi (Play Console shuni
# "optimizatsiya past" deb belgilagan edi) — shu sabab olib tashlandi.

# Play Core (Flutter deferred-components uchun ishlatadi) — loyihada
# ishlatilmasa ham, sinf topilmasa build to'xtab qolmasin.
-dontwarn com.google.android.play.core.**

# Firebase/Firestore — bu loyihada hujjatlar qo'lda Map<String,dynamic>
# orqali parse qilinadi (POJO/@PropertyName ishlatilmaydi), shuning
# uchun maxsus keep qoidasi shart emas — Firebase kutubxonalarining
# o'z consumer-rules.pro fayllari avtomatik qo'shiladi.

# Kotlin metadata — reflection asosidagi kutubxonalar (masalan json
# serializers) uchun xavfsizlik chorasi.
-keepattributes *Annotation*, InnerClasses, Signature, SourceFile, LineNumberTable
-keep class kotlin.Metadata { *; }

# Native metodlar va Parcelable — umumiy xavfsizlik qoidalari.
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
