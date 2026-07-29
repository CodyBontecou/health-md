# UniFFI 0.32 uses JNA direct mapping and reflects over these classes at runtime.
-keep class com.healthmd.core.UniffiLib { *; }
-keep class com.healthmd.core.IntegrityCheckingUniffiLib { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.Library { *; }
-keep class * extends com.sun.jna.Structure { *; }
-keepclassmembers class * extends com.sun.jna.Structure {
    <fields>;
}
-dontwarn com.sun.jna.**
