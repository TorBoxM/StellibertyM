# 保留 JNI 层通过 FindClass/GetMethodID 反射访问的回调接口，避免 release 混淆导致 JNI_OnLoad 失败。
-keep class io.github.stelliberty.android.clash_core.ClashCoreResultCallback {
    *;
}

