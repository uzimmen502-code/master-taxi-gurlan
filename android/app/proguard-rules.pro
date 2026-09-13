# Flutter engine — kod avtomatik kiritiladi, lekin ba'zi eski R8
# versiyalari uchun aniqlik kiritish zarar qilmaydi.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

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
