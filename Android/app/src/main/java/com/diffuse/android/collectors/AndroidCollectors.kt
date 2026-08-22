package com.diffuse.android.collectors

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import android.view.WindowManager
import com.diffuse.android.domain.ChangeSeverity
import com.diffuse.android.domain.CollectionStatus
import com.diffuse.android.domain.ComparisonRule
import com.diffuse.android.domain.Diagnostic
import com.diffuse.android.domain.DeviceIdentity
import com.diffuse.android.domain.EntityIdentity
import com.diffuse.android.domain.EntityKindDescriptor
import com.diffuse.android.domain.PrivacyClassification
import com.diffuse.android.domain.PropertyDescriptor
import com.diffuse.android.domain.PropertyUnit
import com.diffuse.android.domain.PropertyValue
import com.diffuse.android.domain.SectionSchema
import com.diffuse.android.domain.SnapshotEntity
import com.diffuse.android.domain.SnapshotSection
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.NetworkInterface
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

data class CapabilityMetadata(
    val id: String,
    val displayName: String,
    val summary: String,
    val collectionDescription: String,
    val privacy: PrivacyClassification,
    val schema: SectionSchema,
    val enabledByDefault: Boolean = true,
)

interface AndroidCollector {
    val metadata: CapabilityMetadata
    val collectorID: String
    suspend fun collect(context: Context, capturedAt: String): SnapshotSection
}

class AndroidDeviceIdentityProvider(private val context: Context) {
    private val installID: String by lazy {
        val values = context.getSharedPreferences("diffuse.preferences", Context.MODE_PRIVATE)
        values.getString("installIdentifier", null) ?: UUID.randomUUID().toString().also {
            values.edit().putString("installIdentifier", it).apply()
        }
    }

    fun current(): DeviceIdentity {
        val name = runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }
            .getOrNull().orEmpty().ifBlank { Build.MODEL }
        return DeviceIdentity(
            installID, name, Build.MODEL, "Android", Build.VERSION.RELEASE,
            Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown",
        )
    }
}

private fun property(
    key: String,
    name: String,
    unit: PropertyUnit = PropertyUnit.NONE,
    comparison: ComparisonRule = when (unit) {
        PropertyUnit.BYTES -> ComparisonRule.relative(0.01)
        PropertyUnit.PERCENT -> ComparisonRule.numeric(0.05)
        PropertyUnit.SECONDS -> ComparisonRule.relative(0.1)
        PropertyUnit.PATH -> ComparisonRule.PathNormalized
        PropertyUnit.VERSION -> ComparisonRule.SemanticVersion
        PropertyUnit.TIMESTAMP -> ComparisonRule.Ignored
        else -> ComparisonRule.Exact
    },
    severity: ChangeSeverity = ChangeSeverity.NOTABLE,
    privacy: PrivacyClassification = PrivacyClassification.PUBLIC,
    primary: Boolean = false,
    order: Int = 0,
    summary: String? = null,
) = PropertyDescriptor(key, name, summary, unit, comparison, severity, privacy, primary, order)

abstract class BaseCollector : AndroidCollector {
    protected fun section(
        capturedAt: String,
        entities: List<SnapshotEntity>,
        status: CollectionStatus = CollectionStatus.COLLECTED,
        attributes: Map<String, PropertyValue> = emptyMap(),
        diagnostics: List<Diagnostic> = emptyList(),
    ) = SnapshotSection(metadata.id, collectorID, "1.0.0", capturedAt, status = status, schema = metadata.schema, entities = entities, attributes = attributes, diagnostics = diagnostics)
}

class DeviceCollector : BaseCollector() {
    override val collectorID = "android.device.info"
    private val schema = SectionSchema(
        "device.info", "Device", "What this Android device is and which system version it runs.", "hardware", "smartphone",
        PrivacyClassification.LOCAL,
        listOf(EntityKindDescriptor("machine", "Device", "Device", "smartphone", properties = listOf(
            property("model", "Model", severity = ChangeSeverity.CRITICAL, primary = true, order = 0),
            property("modelIdentifier", "Model identifier", severity = ChangeSeverity.CRITICAL, order = 1),
            property("manufacturer", "Manufacturer", severity = ChangeSeverity.SIGNIFICANT, order = 2),
            property("os.version", "Android version", PropertyUnit.VERSION, severity = ChangeSeverity.SIGNIFICANT, primary = true, order = 3),
            property("apiLevel", "API level", PropertyUnit.COUNT, severity = ChangeSeverity.SIGNIFICANT, order = 4),
            property("hostName", "Device name", severity = ChangeSeverity.NOTABLE, privacy = PrivacyClassification.SENSITIVE, order = 5),
            property("architecture", "Architectures", severity = ChangeSeverity.SIGNIFICANT, order = 6),
        ))), displayOrder = 10,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Reads manufacturer, model, Android/API version, supported CPU architectures, and the user-visible device name. It does not read advertising, hardware, or account identifiers.",
        schema.privacy, schema,
    )

    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val name = runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }.getOrNull().orEmpty().ifBlank { Build.MODEL }
        val entity = SnapshotEntity(
            EntityIdentity.create("machine", "primary"), Build.MODEL, "Android ${Build.VERSION.RELEASE}",
            mapOf(
                "model" to PropertyValue.string(Build.MODEL),
                "modelIdentifier" to PropertyValue.identifier(Build.DEVICE),
                "manufacturer" to PropertyValue.string(Build.MANUFACTURER),
                "os.version" to PropertyValue.version(Build.VERSION.RELEASE),
                "apiLevel" to PropertyValue.integer(Build.VERSION.SDK_INT.toLong()),
                "hostName" to PropertyValue.string(name),
                "architecture" to PropertyValue.list(Build.SUPPORTED_ABIS.map(PropertyValue::string)),
            ), tags = if (Build.FINGERPRINT.contains("generic")) setOf("emulator") else emptySet(),
        )
        return section(capturedAt, listOf(entity))
    }
}

class SystemCollector : BaseCollector() {
    override val collectorID = "android.system.info"
    private val schema = SectionSchema(
        "system.info", "System", "Android version, boot time, locale, time zone, memory and power state.", "system", "memory",
        PrivacyClassification.LOCAL,
        listOf(EntityKindDescriptor("system", "System", "System", "memory", properties = listOf(
            property("os.name", "Operating system", severity = ChangeSeverity.CRITICAL, primary = true, order = 0),
            property("os.version", "Version", PropertyUnit.VERSION, severity = ChangeSeverity.SIGNIFICANT, primary = true, order = 1),
            property("kernelVersion", "Kernel", severity = ChangeSeverity.NOTABLE, order = 2),
            property("uptime", "Uptime", PropertyUnit.SECONDS, ComparisonRule.Ignored, ChangeSeverity.INFORMATIONAL, order = 3),
            property("bootedAt", "Last booted", PropertyUnit.TIMESTAMP, ComparisonRule.numeric(120.0), ChangeSeverity.SIGNIFICANT, order = 4),
            property("locale", "Locale", severity = ChangeSeverity.NOTABLE, order = 5),
            property("timeZone", "Time zone", severity = ChangeSeverity.NOTABLE, order = 6),
            property("thermalState", "Thermal state", severity = ChangeSeverity.NOTABLE, order = 7),
            property("lowPowerMode", "Battery Saver", severity = ChangeSeverity.NOTABLE, order = 8),
            property("physicalMemory", "Physical memory", PropertyUnit.BYTES, ComparisonRule.Exact, ChangeSeverity.SIGNIFICANT, order = 9),
            property("coreCount", "Logical cores", PropertyUnit.COUNT, severity = ChangeSeverity.SIGNIFICANT, order = 10),
        ))), displayOrder = 0,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Reads Android and kernel versions, uptime, locale, time zone, memory size, processor count, Battery Saver, and the public thermal status. No account or file data is read.",
        schema.privacy, schema,
    )

    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val power = context.getSystemService(PowerManager::class.java)
        val memory = ActivityManager.MemoryInfo().also { context.getSystemService(ActivityManager::class.java).getMemoryInfo(it) }
        val uptime = SystemClock.elapsedRealtime() / 1000.0
        val boot = Instant.ofEpochMilli(System.currentTimeMillis() - SystemClock.elapsedRealtime()).toString()
        val thermal = if (Build.VERSION.SDK_INT >= 29) when (power.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "Nominal"
            PowerManager.THERMAL_STATUS_LIGHT -> "Light"
            PowerManager.THERMAL_STATUS_MODERATE -> "Moderate"
            PowerManager.THERMAL_STATUS_SEVERE -> "Severe"
            PowerManager.THERMAL_STATUS_CRITICAL -> "Critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "Emergency"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "Shutdown"
            else -> "Unknown"
        } else "Unavailable"
        val entity = SnapshotEntity(
            EntityIdentity.create("system", "primary"), "Android", Build.VERSION.RELEASE,
            mapOf(
                "os.name" to PropertyValue.string("Android"),
                "os.version" to PropertyValue.version(Build.VERSION.RELEASE),
                "kernelVersion" to PropertyValue.string(System.getProperty("os.version") ?: "unknown"),
                "uptime" to PropertyValue.duration(uptime),
                "bootedAt" to PropertyValue.date(boot),
                "locale" to PropertyValue.string(Locale.getDefault().toLanguageTag()),
                "timeZone" to PropertyValue.string(ZoneId.systemDefault().id),
                "thermalState" to PropertyValue.string(thermal),
                "lowPowerMode" to PropertyValue.boolean(power.isPowerSaveMode),
                "physicalMemory" to PropertyValue.bytes(memory.totalMem),
                "coreCount" to PropertyValue.integer(Runtime.getRuntime().availableProcessors().toLong()),
            ),
        )
        return section(capturedAt, listOf(entity))
    }
}

class BatteryCollector : BaseCollector() {
    override val collectorID = "android.power.battery"
    private val schema = SectionSchema(
        "power.battery", "Battery", "Charge level, charging source, health and Battery Saver.", "power", "battery_full",
        PrivacyClassification.LOCAL,
        listOf(EntityKindDescriptor(
            "battery", "Battery", "Battery", "battery_full",
            additionSeverity = ChangeSeverity.INFORMATIONAL,
            removalSeverity = ChangeSeverity.NOTABLE,
            properties = listOf(
            property("batteryLevel", "Charge", PropertyUnit.PERCENT, ComparisonRule.numeric(0.05), ChangeSeverity.INFORMATIONAL, primary = true, order = 0),
            property("batteryState", "State", severity = ChangeSeverity.INFORMATIONAL, primary = true, order = 1),
            property("lowPowerMode", "Battery Saver", severity = ChangeSeverity.NOTABLE, order = 2),
            property("health", "Health", severity = ChangeSeverity.NOTABLE, order = 3),
            property("temperature", "Temperature", PropertyUnit.CELSIUS, ComparisonRule.numeric(2.0), ChangeSeverity.INFORMATIONAL, order = 4),
            ),
        )), displayOrder = 25,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Reads the sticky system battery broadcast and Battery Saver state: charge percentage, charging state, health, and temperature.",
        schema.privacy, schema,
    )

    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return section(capturedAt, emptyList(), CollectionStatus.UNAVAILABLE)
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = when (intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
            BatteryManager.BATTERY_STATUS_FULL -> "Full"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "On battery"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not charging"
            else -> "Unknown"
        }
        val health = when (intent.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheating"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over voltage"
            BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
            else -> "Unknown"
        }
        val power = context.getSystemService(PowerManager::class.java)
        val entity = SnapshotEntity(
            EntityIdentity.create("battery", "internal"), "Battery", status,
            mapOf(
                "batteryLevel" to PropertyValue.percentage(if (level >= 0 && scale > 0) level.toDouble() / scale else 0.0),
                "batteryState" to PropertyValue.string(status),
                "lowPowerMode" to PropertyValue.boolean(power.isPowerSaveMode),
                "health" to PropertyValue.string(health),
                "temperature" to PropertyValue.double(intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0),
            ),
        )
        return section(capturedAt, listOf(entity), if (level >= 0) CollectionStatus.COLLECTED else CollectionStatus.PARTIAL)
    }
}

class DisplayCollector : BaseCollector() {
    override val collectorID = "android.display.screen"
    private val schema = SectionSchema(
        "display.screen", "Screen", "Screen resolution, density and refresh ceiling.", "display", "smartphone",
        PrivacyClassification.PUBLIC,
        listOf(EntityKindDescriptor("screen", "Screen", "Screens", "smartphone", properties = listOf(
            property("resolution", "Resolution", PropertyUnit.PIXELS, severity = ChangeSeverity.SIGNIFICANT, primary = true, order = 0),
            property("density", "Density", comparison = ComparisonRule.numeric(0.01), severity = ChangeSeverity.SIGNIFICANT, order = 1),
            property("refreshRate", "Max refresh", PropertyUnit.HERTZ, ComparisonRule.numeric(1.0), ChangeSeverity.NOTABLE, order = 2),
        ))), displayOrder = 21,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Reads pixel dimensions, logical density, and supported display refresh modes. It never captures screen contents.",
        schema.privacy, schema,
    )

    @Suppress("DEPRECATION")
    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val metrics = context.resources.displayMetrics
        val display = context.getSystemService(WindowManager::class.java).defaultDisplay
        val refresh = display.supportedModes.maxOfOrNull { it.refreshRate }?.toDouble() ?: display.refreshRate.toDouble()
        val resolution = "${metrics.widthPixels} × ${metrics.heightPixels}"
        val entity = SnapshotEntity(
            EntityIdentity.create("screen", "main"), "Main screen", resolution,
            mapOf(
                "resolution" to PropertyValue.string(resolution),
                "density" to PropertyValue.double(metrics.density.toDouble()),
                "refreshRate" to PropertyValue.double(refresh),
            ),
        )
        return section(capturedAt, listOf(entity))
    }
}

class StorageCollector : BaseCollector() {
    override val collectorID = "android.storage.volumes"
    private val schema = SectionSchema(
        "storage.volumes", "Storage", "Capacity and free space on the app-accessible data volume.", "storage", "storage",
        PrivacyClassification.LOCAL,
        listOf(EntityKindDescriptor("volume", "Volume", "Volumes", "storage", properties = listOf(
            property("availableCapacity", "Available", PropertyUnit.BYTES, ComparisonRule.relative(0.01), ChangeSeverity.INFORMATIONAL, primary = true, order = 0),
            property("totalCapacity", "Capacity", PropertyUnit.BYTES, ComparisonRule.Exact, ChangeSeverity.SIGNIFICANT, order = 1),
            property("usedCapacity", "Used", PropertyUnit.BYTES, ComparisonRule.relative(0.01), ChangeSeverity.INFORMATIONAL, order = 2),
            property("isRemovable", "Removable", severity = ChangeSeverity.NOTABLE, order = 3),
        ))),
        listOf(property("availableCapacity", "Total free space", PropertyUnit.BYTES, ComparisonRule.relative(0.01), ChangeSeverity.INFORMATIONAL)),
        40,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Reads total and free byte counts for the private app data volume. No directories, file names, or file contents are enumerated.",
        schema.privacy, schema,
    )

    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val stats = StatFs(context.filesDir.absolutePath)
        val total = stats.totalBytes
        val free = stats.availableBytes
        val removable = false // filesDir is always the app-private internal data volume.
        val entity = SnapshotEntity(
            EntityIdentity.create("volume", "app-data"), "App data volume", if (removable) "Removable" else "Internal",
            mapOf(
                "availableCapacity" to PropertyValue.bytes(free),
                "totalCapacity" to PropertyValue.bytes(total),
                "usedCapacity" to PropertyValue.bytes((total - free).coerceAtLeast(0)),
                "isRemovable" to PropertyValue.boolean(removable),
            ), tags = setOf(if (removable) "removable" else "internal"),
        )
        return section(capturedAt, listOf(entity), attributes = mapOf("availableCapacity" to PropertyValue.bytes(free)))
    }
}

class NetworkPathCollector : BaseCollector() {
    override val collectorID = "android.network.path"
    private val schema = SectionSchema(
        "network.path", "Connectivity", "How this device is currently reaching the network.", "network", "wifi",
        PrivacyClassification.LOCAL,
        listOf(EntityKindDescriptor("networkPath", "Connection", "Connections", "wifi", properties = listOf(
            property("interfaceType", "Connection", severity = ChangeSeverity.SIGNIFICANT, primary = true, order = 0),
            property("pathStatus", "Status", severity = ChangeSeverity.SIGNIFICANT, primary = true, order = 1),
            property("usesVPN", "VPN", severity = ChangeSeverity.SIGNIFICANT, order = 2),
            property("isExpensive", "Metered", severity = ChangeSeverity.NOTABLE, order = 3),
            property("isConstrained", "Restricted", severity = ChangeSeverity.NOTABLE, order = 4),
            property("validated", "Validated", severity = ChangeSeverity.NOTABLE, order = 5),
        ))), displayOrder = 31,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Reads the active network's transport type, metered/restricted state, validation, and VPN transport. It does not send traffic or inspect packets.",
        schema.privacy, schema,
    )

    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val network = manager.activeNetwork
        val capabilities = network?.let(manager::getNetworkCapabilities)
        val type = when {
            capabilities == null -> "None"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "VPN"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "Bluetooth"
            else -> "Other"
        }
        val connected = capabilities != null && capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        val entity = SnapshotEntity(
            EntityIdentity.create("networkPath", "default"), type, if (connected) "Connected" else "Unavailable",
            mapOf(
                "interfaceType" to PropertyValue.string(type),
                "pathStatus" to PropertyValue.string(if (connected) "Connected" else "Unavailable"),
                "usesVPN" to PropertyValue.boolean(capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true),
                "isExpensive" to PropertyValue.boolean(manager.isActiveNetworkMetered),
                "isConstrained" to PropertyValue.boolean(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED) == false),
                "validated" to PropertyValue.boolean(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            ), tags = if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) setOf("vpn") else emptySet(),
        )
        return section(capturedAt, listOf(entity))
    }
}

class NetworkInterfacesCollector : BaseCollector() {
    override val collectorID = "android.network.interfaces"
    private val schema = SectionSchema(
        "network.interfaces", "Network interfaces", "Which network interfaces exist and which addresses they hold.", "network", "lan",
        PrivacyClassification.SENSITIVE,
        listOf(EntityKindDescriptor("networkInterface", "Interface", "Interfaces", "lan", properties = listOf(
            property("isActive", "Active", severity = ChangeSeverity.SIGNIFICANT, primary = true, order = 0),
            property("ipv4Address", "IPv4 address", severity = ChangeSeverity.NOTABLE, privacy = PrivacyClassification.SENSITIVE, order = 1),
            property("ipv6Address", "IPv6 address", severity = ChangeSeverity.INFORMATIONAL, privacy = PrivacyClassification.SENSITIVE, order = 2),
            property("interfaceType", "Type", severity = ChangeSeverity.NOTABLE, order = 3),
        ))), displayOrder = 30,
    )
    override val metadata = CapabilityMetadata(
        schema.capability, schema.displayName, schema.summary,
        "Lists non-loopback interface names, whether each is active, and local IP addresses. No traffic is inspected; addresses are redacted from standard exports.",
        schema.privacy, schema,
    )

    override suspend fun collect(context: Context, capturedAt: String): SnapshotSection {
        val diagnostics = mutableListOf<Diagnostic>()
        val entities = runCatching {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().filterNot { it.isLoopback }.sortedBy { it.name }.map { network ->
                val addresses = network.inetAddresses.toList().filterNot { it.isLoopbackAddress || it.isLinkLocalAddress }
                val ipv4 = addresses.filterIsInstance<Inet4Address>().firstOrNull()?.hostAddress
                val ipv6 = addresses.filterIsInstance<Inet6Address>().firstOrNull()?.hostAddress?.substringBefore('%')
                val type = when {
                    network.name.startsWith("wlan") -> "Wi-Fi"
                    network.name.startsWith("rmnet") || network.name.startsWith("ccmni") -> "Cellular"
                    network.name.startsWith("tun") -> "Tunnel or VPN"
                    network.name.startsWith("eth") -> "Ethernet"
                    else -> "Other"
                }
                SnapshotEntity(
                    EntityIdentity.create("networkInterface", network.name), "${network.name} · $type", network.name,
                    mapOf(
                        "isActive" to PropertyValue.boolean(network.isUp),
                        "ipv4Address" to (ipv4?.let(PropertyValue::identifier) ?: PropertyValue.Absent),
                        "ipv6Address" to (ipv6?.let(PropertyValue::identifier) ?: PropertyValue.Absent),
                        "interfaceType" to PropertyValue.string(type),
                    ), tags = if (network.isUp) setOf("active") else emptySet(),
                )
            }
        }.getOrElse {
            diagnostics += Diagnostic(Diagnostic.Level.ERROR, "Could not enumerate network interfaces", it.message)
            emptyList()
        }
        return section(capturedAt, entities, if (diagnostics.isEmpty()) CollectionStatus.COLLECTED else CollectionStatus.FAILED, diagnostics = diagnostics)
    }
}

class AndroidCapabilityRegistry {
    val collectors: List<AndroidCollector> = listOf(
        DeviceCollector(), SystemCollector(), BatteryCollector(), DisplayCollector(), StorageCollector(),
        NetworkInterfacesCollector(), NetworkPathCollector(),
    ).sortedBy { it.metadata.id }
}
