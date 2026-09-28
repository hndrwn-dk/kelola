# WorkManager opens WorkDatabase via reflection. AGP 9 R8 full mode
# strips no-arg constructors; 2.9.x then crashes at process start:
# Failed to create an instance of class androidx.work.impl.WorkDatabase.canonicalName
# { *; } does not keep constructors. Keep <init> across the package.
-keep class androidx.work.** { <init>(...); }
-keep class androidx.work.impl.** { *; }
