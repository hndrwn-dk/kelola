# WorkManager opens WorkDatabase via reflection. AGP 9 R8 full mode
# strips no-arg constructors; 2.9.x then crashes at process start:
# Failed to create an instance of class androidx.work.impl.WorkDatabase.canonicalName
# { *; } does not keep constructors. Keep <init> across the package.
-keep class androidx.work.** { <init>(...); }
-keep class androidx.work.impl.** { *; }

# FleetWatchWorker is enqueued by class name; keep the WorkManager constructor.
-keep class com.tursinalabs.kelola.FleetWatchWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Play Core is referenced transitively by billing; not all classes ship on device.
-dontwarn com.google.android.play.core.**
