package com.kishormainali.fl_updater

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlUpdaterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var appUpdateManager: AppUpdateManager? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.kishormainali.fl_updater")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        appUpdateManager = AppUpdateManagerFactory.create(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        appUpdateManager = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        appUpdateManager = AppUpdateManagerFactory.create(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activity = null
        appUpdateManager = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        if (call.method == "openStore") {
            val packageId = call.argument<String>("androidPackageId")?.takeIf { it.isNotEmpty() }
                ?: context.packageName
            openStore(packageId, result)
        } else {
            result.notImplemented()
        }
    }

    private fun openStore(packageId: String, result: Result) {
        val manager = appUpdateManager
        val currentActivity = activity
        if (manager == null || currentActivity == null) {
            openWebFallback(packageId, result)
            return
        }

        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                val canUpdateImmediately =
                    info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                        info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
                if (canUpdateImmediately) {
                    try {
                        manager.startUpdateFlowForResult(
                            info,
                            currentActivity,
                            AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                            REQUEST_CODE_IMMEDIATE_UPDATE,
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        openWebFallback(packageId, result)
                    }
                } else {
                    openWebFallback(packageId, result)
                }
            }
            .addOnFailureListener {
                openWebFallback(packageId, result)
            }
    }

    private fun openWebFallback(packageId: String, result: Result) {
        try {
            val webIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$packageId"),
            )
            webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(webIntent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("CANNOT_OPEN", "Could not open Play Store", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val REQUEST_CODE_IMMEDIATE_UPDATE = 20255
    }
}
