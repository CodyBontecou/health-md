# Cold flavor only. Finite OS/RN entry points; optimization otherwise retained.
-keep class com.healthmd.effecthostcandidate.ColdProbeApplication { public <init>(); }
-keep class com.healthmd.effecthostcandidate.ColdProbeWorker { public <init>(android.content.Context, androidx.work.WorkerParameters); }
-keep class com.healthmd.effecthostcandidate.ColdProbeControlReceiver { public <init>(); public void onReceive(android.content.Context, android.content.Intent); }
-keepclassmembers class com.healthmd.effecthostcandidate.ColdProbeModule { @com.facebook.react.bridge.ReactMethod <methods>; }
# Exact shared AndroidTest/runtime ABI identities and members; cold-only.
-keep class androidx.work.Data$Builder {
    <init>();
    androidx.work.Data build();
    androidx.work.Data$Builder putBoolean(java.lang.String,boolean);
    androidx.work.Data$Builder putInt(java.lang.String,int);
    androidx.work.Data$Builder putString(java.lang.String,java.lang.String);
}

-keep class androidx.work.Data {

}

-keep class androidx.work.OneTimeWorkRequest$Builder {
    <init>(java.lang.Class);
}

-keep class androidx.work.OneTimeWorkRequest {

}

-keep class androidx.work.Operation {
    com.google.common.util.concurrent.ListenableFuture getResult();
}

-keep class androidx.work.WorkManager$Companion {
    androidx.work.WorkManager getInstance(android.content.Context);
}

-keep class androidx.work.WorkManager {
    androidx.work.WorkManager$Companion Companion;
    androidx.work.Operation enqueue(java.util.List);
}

-keep class androidx.work.WorkRequest$Builder {
    androidx.work.WorkRequest build();
    androidx.work.WorkRequest$Builder setInitialDelay(long,java.util.concurrent.TimeUnit);
    androidx.work.WorkRequest$Builder setInputData(androidx.work.Data);
}

-keep class androidx.work.WorkRequest {
    java.util.UUID getId();
}

-keep class com.facebook.react.ReactApplication {

}

-keep class com.facebook.react.ReactHost {

}

-keep class com.google.common.util.concurrent.ListenableFuture {

}

-keep class com.healthmd.effecthostcandidate.ColdEvidence {
    com.healthmd.effecthostcandidate.ColdEvidence INSTANCE;
    boolean cleanupComplete(int,int,int,boolean);
    java.lang.String controlNonce(java.lang.String,java.lang.String);
    boolean publishedComplete(java.lang.String,int);
    java.lang.String sameBoot(java.lang.Integer,java.lang.Integer);
    boolean sameProcess(java.lang.String,java.lang.String);
}

-keep class com.healthmd.effecthostcandidate.ColdFrame {
    int getTtl();
}

-keep class com.healthmd.effecthostcandidate.ColdParser {
    com.healthmd.effecthostcandidate.ColdParser INSTANCE;
    void clock(long,long,int);
    kotlin.Pair data(androidx.work.Data);
    long unsigned(java.lang.String,long);
}

-keep class com.healthmd.effecthostcandidate.ColdProbeBridgeKt {
    java.util.List getColdCases();
}

-keep class com.healthmd.effecthostcandidate.ColdRefusal {
    java.lang.String getCode();
}

-keep class com.healthmd.effecthostcandidate.ColdRegistry {
    com.healthmd.effecthostcandidate.ColdRegistry INSTANCE;
    kotlin.Pair issue(android.content.Context,java.util.List,java.lang.String);
}

-keep class com.healthmd.effecthostcandidate.HostProbeApplication {
    com.facebook.react.ReactHost getReactHost();
}

-keep class kotlin.Pair {
    java.lang.Object component1();
    java.lang.Object component2();
}

-keep class kotlin.TuplesKt {
    kotlin.Pair to(java.lang.Object,java.lang.Object);
}

-keep class kotlin.text.Regex {
    boolean matches(java.lang.CharSequence);
}

-keep class androidx.concurrent.futures.SuspendToFutureAdapter {
    public static final androidx.concurrent.futures.SuspendToFutureAdapter INSTANCE;
    public static com.google.common.util.concurrent.ListenableFuture launchFuture$default(androidx.concurrent.futures.SuspendToFutureAdapter,kotlin.coroutines.CoroutineContext,boolean,kotlin.jvm.functions.Function2,int,java.lang.Object);
}

-keep class kotlin.Function {
}

-keep class kotlin.coroutines.CoroutineContext {
}

-keep class kotlin.jvm.functions.Function2 {
}
