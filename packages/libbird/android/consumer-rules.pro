# Keep SDL Java API used by native JNI registration in engine startup.
# Without these rules, release minification can strip/rename methods and
# trigger ClassNotFoundException/UnsatisfiedLinkError at runtime.
-keep class org.libsdl.app.** { *; }
