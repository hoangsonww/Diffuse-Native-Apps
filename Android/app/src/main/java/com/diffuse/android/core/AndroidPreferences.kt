package com.diffuse.android.core

import android.content.Context
import com.diffuse.android.domain.RedactionPolicy
import com.diffuse.android.domain.RetentionPolicy

class AndroidPreferences(context: Context) {
    private val values = context.getSharedPreferences("diffuse.preferences", Context.MODE_PRIVATE)

    enum class Cadence(val hours: Long?) { OFF(null), HOURLY(1), FOUR_HOURS(4), DAILY(24) }

    var cadence: Cadence
        get() = runCatching { Cadence.valueOf(values.getString("cadence", Cadence.FOUR_HOURS.name)!!) }.getOrDefault(Cadence.FOUR_HOURS)
        set(value) { values.edit().putString("cadence", value.name).apply() }
    var skipUnchanged: Boolean
        get() = values.getBoolean("skipUnchanged", true)
        set(value) { values.edit().putBoolean("skipUnchanged", value).apply() }
    var retentionDays: Int
        get() = values.getInt("retentionDays", 90)
        set(value) { values.edit().putInt("retentionDays", value).apply() }
    var maximumMegabytes: Int
        get() = values.getInt("maximumMegabytes", 1024)
        set(value) { values.edit().putInt("maximumMegabytes", value).apply() }
    var redaction: RedactionPolicy
        get() = runCatching { RedactionPolicy.valueOf(values.getString("redaction", RedactionPolicy.STANDARD.name)!!) }.getOrDefault(RedactionPolicy.STANDARD)
        set(value) { values.edit().putString("redaction", value.name).apply() }

    fun isEnabled(id: String, default: Boolean): Boolean = values.getBoolean("capability.$id", default)
    fun setEnabled(id: String, enabled: Boolean) { values.edit().putBoolean("capability.$id", enabled).apply() }

    val retentionPolicy get() = RetentionPolicy(
        days = retentionDays,
        maximumBytes = maximumMegabytes.takeIf { it > 0 }?.toLong()?.times(1_048_576),
    )
}
