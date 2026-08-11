# Health Connect
-keep class androidx.health.connect.** { *; }

# Kotlinx Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.healthmd.**$$serializer { *; }
-keepclassmembers class com.healthmd.** {
    *** Companion;
}
-keepclasseswithmembers class com.healthmd.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Room
-keep class * extends androidx.room.RoomDatabase
-dontwarn androidx.room.paging.**

# PDFBox-Android optionally discovers Gemalto's JPEG 2000 codec. The report writer does not
# decode or encode JPEG 2000, so these absent optional classes are safe to leave unresolved.
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder
