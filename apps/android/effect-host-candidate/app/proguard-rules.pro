-keep class com.healthmd.effecthostcandidate.NativeProbeModule { *; }
-keep class com.healthmd.effecthostcandidate.NativeProbePackage { *; }
-keep class com.healthmd.effecthostcandidate.ProbeRuntime { *; }
-keep class com.facebook.react.defaults.DefaultNewArchitectureEntryPoint { *; }

# ErrorProne test annotations retain javac Modifier[] metadata at CLASS retention only.
# The private test APK never executes this unavailable Java compiler enum.
-dontwarn javax.lang.model.element.Modifier
