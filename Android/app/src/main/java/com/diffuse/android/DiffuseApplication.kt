package com.diffuse.android

import android.app.Application
import com.diffuse.android.core.AndroidPreferences
import com.diffuse.android.core.SnapshotWorker

class DiffuseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val preferences = AndroidPreferences(this)
        SnapshotWorker.schedule(this, preferences.cadence)
    }
}
