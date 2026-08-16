import com.android.aapt.Resources.XmlAttribute;
import com.android.aapt.Resources.XmlElement;
import com.android.aapt.Resources.XmlNode;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.zip.ZipFile;

/** Parses a phone/Wear AAPT2 protobuf manifest against caller-supplied release identity. */
public final class WearBundleManifestVerifier {
    private static final String ANDROID = "http://schemas.android.com/apk/res/android";
    private static final String HEALTHMD_AGPL_SHA256 =
        "0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0";

    public static void main(String[] args) throws Exception {
        if (args.length != 7) {
            fail("usage: WearBundleManifestVerifier <wear|phone> app.aab package versionCode versionName minSdk targetSdk");
        }
        String formFactor = args[0];
        Path bundle = Path.of(args[1]);
        String expectedPackage = args[2];
        String expectedVersionCode = args[3];
        String expectedVersionName = args[4];
        String expectedMinSdk = args[5];
        String expectedTargetSdk = args[6];
        require("wear".equals(formFactor) || "phone".equals(formFactor), "unknown form factor");
        require(!expectedPackage.isBlank() && !expectedVersionCode.isBlank() &&
            !expectedVersionName.isBlank() && !expectedMinSdk.isBlank() && !expectedTargetSdk.isBlank(),
            "expected identity values must be nonblank");

        XmlElement manifest = readManifest(bundle, formFactor);
        require("manifest".equals(manifest.getName()), "root is not manifest");
        verifyStaticCapability(bundle, expectedPackage,
            "wear".equals(formFactor) ? "healthmd_watch_sync" : "healthmd_phone_sync");
        require(expectedPackage.equals(attr(manifest, "package")), "wrong package");
        require(expectedVersionCode.equals(attr(manifest, ANDROID, "versionCode")), "wrong packaged versionCode");
        require(expectedVersionName.equals(attr(manifest, ANDROID, "versionName")), "wrong packaged versionName");

        XmlElement sdk = one(manifest, "uses-sdk");
        require(expectedMinSdk.equals(attr(sdk, ANDROID, "minSdkVersion")), "wrong packaged minSdk");
        require(expectedTargetSdk.equals(attr(sdk, ANDROID, "targetSdkVersion")), "wrong packaged targetSdk");
        XmlElement app = one(manifest, "application");
        if ("phone".equals(formFactor)) {
            List<XmlElement> services = elements(app, "service");
            List<XmlElement> listeners = services.stream()
                .filter(e -> "com.healthmd.wear.WearPhoneDataLayerService".equals(attr(e, ANDROID, "name")))
                .toList();
            require(listeners.size() == 1, "phone Data Layer listener inventory differs");
            XmlElement listener = listeners.get(0);
            require("true".equals(attr(listener, ANDROID, "exported")), "phone Data Layer listener missing");
            require(dataLayerListenerServices(services).equals(List.of(listener)),
                "unexpected phone Data Layer listener service");
            List<XmlElement> filters = elements(listener, "intent-filter");
            require(filters.size() == 2, "phone Data Layer intent-filter inventory differs");
            long messageFilters = filters.stream().filter(filter -> exactFilter(
                filter,
                Set.of("com.google.android.gms.wearable.MESSAGE_RECEIVED"),
                Set.of("scheme", "host", "pathPrefix"),
                "/healthmd/wear"
            )).count();
            require(messageFilters == 1, "phone message listener missing or mis-scoped");
            long capabilityFilters = filters.stream().filter(filter -> exactFilter(
                filter,
                Set.of("com.google.android.gms.wearable.CAPABILITY_CHANGED"),
                Set.of("scheme", "host"),
                ""
            )).count();
            require(capabilityFilters == 1, "phone capability-change listener missing or path-restricted");
            System.out.println("Packaged phone protobuf manifest identity valid");
            return;
        }
        verifyBundledFontLicenses(bundle);

        XmlElement watch = elements(manifest, "uses-feature").stream()
            .filter(e -> "android.hardware.type.watch".equals(attr(e, ANDROID, "name"))).findFirst().orElse(null);
        require(watch != null && "true".equals(attr(watch, ANDROID, "required")), "required watch feature missing");

        Set<String> permissions = elements(manifest, "uses-permission").stream()
            .map(e -> attr(e, ANDROID, "name")).collect(java.util.stream.Collectors.toSet());
        Set<String> expectedPermissions = Set.of(
            "android.permission.RECEIVE_BOOT_COMPLETED",
            "com.healthmd.android.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
        );
        require(expectedPermissions.equals(permissions), "packaged permission set differs");
        require(permissions.stream().noneMatch(name ->
            name.contains("HEALTH") || name.contains("BODY_SENSORS") || name.contains("ACTIVITY_RECOGNITION") ||
            name.contains("INTERNET") || name.contains("LOCATION")), "forbidden watch permission packaged");

        require("false".equals(attr(app, ANDROID, "allowBackup")), "backup must be disabled");
        require(meta(app, "com.google.android.wearable.standalone", "false"), "standalone=false missing");
        List<XmlElement> diagnosticProviders = elements(app, "provider").stream()
            .filter(e -> "com.healthmd.wear.sync.WearDiagnosticsProvider".equals(attr(e, ANDROID, "name")))
            .toList();
        require(diagnosticProviders.size() == 1, "diagnostics provider identity differs");
        XmlElement diagnostics = diagnosticProviders.get(0);
        require("com.healthmd.android.wear.diagnostics".equals(attr(diagnostics, ANDROID, "authorities")), "diagnostics authority differs");
        require("true".equals(attr(diagnostics, ANDROID, "exported")), "diagnostics provider not exported");
        require("android.permission.DUMP".equals(attr(diagnostics, ANDROID, "permission")), "diagnostics provider lacks DUMP protection");

        List<XmlElement> services = elements(app, "service");
        Set<String> expectedTiles = Set.of(
            "com.healthmd.wear.surface.DailyActivityTileService",
            "com.healthmd.wear.surface.RecoveryTileService"
        );
        Set<String> expectedComplications = Set.of(
            "com.healthmd.wear.surface.DailyActivityComplicationService",
            "com.healthmd.wear.surface.RecoveryComplicationService",
            "com.healthmd.wear.surface.StepsComplicationService",
            "com.healthmd.wear.surface.MoveComplicationService",
            "com.healthmd.wear.surface.ExerciseComplicationService",
            "com.healthmd.wear.surface.SleepComplicationService",
            "com.healthmd.wear.surface.RestingHeartRateComplicationService",
            "com.healthmd.wear.surface.AverageHeartRateComplicationService",
            "com.healthmd.wear.surface.HrvComplicationService",
            "com.healthmd.wear.surface.BloodOxygenComplicationService"
        );
        Set<String> actualTiles = services.stream().map(e -> attr(e, ANDROID, "name"))
            .filter(name -> name.endsWith("TileService")).collect(java.util.stream.Collectors.toSet());
        Set<String> actualComplications = services.stream().map(e -> attr(e, ANDROID, "name"))
            .filter(name -> name.endsWith("ComplicationService")).collect(java.util.stream.Collectors.toSet());
        require(expectedTiles.equals(actualTiles), "packaged Tile identity set differs");
        require(expectedComplications.equals(actualComplications), "packaged complication identity set differs");
        for (XmlElement service : services) {
            String name = attr(service, ANDROID, "name");
            if (name.endsWith("TileService")) {
                require("true".equals(attr(service, ANDROID, "exported")), name + " not exported");
                require("com.google.android.wearable.permission.BIND_TILE_PROVIDER".equals(attr(service, ANDROID, "permission")), name + " bind permission missing");
            } else if (name.endsWith("ComplicationService")) {
                require("true".equals(attr(service, ANDROID, "exported")), name + " not exported");
                require("com.google.android.wearable.permission.BIND_COMPLICATION_PROVIDER".equals(attr(service, ANDROID, "permission")), name + " bind permission missing");
            }
        }
        List<XmlElement> listeners = services.stream()
            .filter(e -> "com.healthmd.wear.sync.WearDataLayerService".equals(attr(e, ANDROID, "name")))
            .toList();
        require(listeners.size() == 1, "Wear Data Layer listener inventory differs");
        XmlElement listener = listeners.get(0);
        require("true".equals(attr(listener, ANDROID, "exported")), "Data Layer listener missing");
        require(dataLayerListenerServices(services).equals(List.of(listener)),
            "unexpected Wear Data Layer listener service");
        List<XmlElement> listenerFilters = elements(listener, "intent-filter");
        require(listenerFilters.size() == 1 && exactFilter(
            listenerFilters.get(0),
            Set.of(
                "com.google.android.gms.wearable.DATA_CHANGED",
                "com.google.android.gms.wearable.MESSAGE_RECEIVED"
            ),
            Set.of("scheme", "host", "pathPrefix"),
            "/healthmd/wear"
        ), "Wear Data Layer actions/path filter missing or split incorrectly");
        System.out.println("Packaged Wear protobuf manifest valid");
    }

    private static List<XmlElement> dataLayerListenerServices(List<XmlElement> services) {
        return services.stream().filter(service -> descendants(service, "action").stream()
            .map(action -> attr(action, ANDROID, "name"))
            .anyMatch(name -> name.startsWith("com.google.android.gms.wearable."))).toList();
    }

    private static boolean exactFilter(
        XmlElement filter,
        Set<String> expectedActions,
        Set<String> expectedDataAttributes,
        String expectedPathPrefix
    ) {
        List<XmlElement> actionElements = elements(filter, "action");
        Set<String> actions = actionElements.stream().map(action -> attr(action, ANDROID, "name"))
            .collect(java.util.stream.Collectors.toSet());
        List<XmlElement> dataElements = elements(filter, "data");
        if (actionElements.size() != expectedActions.size() || !actions.equals(expectedActions) || dataElements.size() != 1 ||
            !elements(filter, "category").isEmpty()) return false;
        XmlElement data = dataElements.get(0);
        Set<String> attributeNames = data.getAttributeList().stream()
            .filter(attribute -> ANDROID.equals(attribute.getNamespaceUri()))
            .map(XmlAttribute::getName)
            .collect(java.util.stream.Collectors.toSet());
        return data.getAttributeCount() == expectedDataAttributes.size() &&
            attributeNames.equals(expectedDataAttributes) &&
            "wear".equals(attr(data, ANDROID, "scheme")) &&
            "*".equals(attr(data, ANDROID, "host")) &&
            expectedPathPrefix.equals(attr(data, ANDROID, "pathPrefix"));
    }

    private static void verifyStaticCapability(Path bundle, String expectedPackage, String expectedCapability)
        throws Exception {
        com.android.aapt.Resources.ResourceTable table;
        try (ZipFile zip = new ZipFile(bundle.toFile())) {
            var entry = zip.getEntry("base/resources.pb");
            require(entry != null, "compiled resources table missing");
            try (InputStream input = zip.getInputStream(entry)) {
                table = com.android.aapt.Resources.ResourceTable.parseFrom(input);
            }
        }
        List<com.android.aapt.Resources.Entry> entries = table.getPackageList().stream()
            .filter(pkg -> expectedPackage.equals(pkg.getPackageName()))
            .flatMap(pkg -> pkg.getTypeList().stream())
            .filter(type -> "array".equals(type.getName()))
            .flatMap(type -> type.getEntryList().stream())
            .filter(entry -> "android_wear_capabilities".equals(entry.getName()))
            .toList();
        require(entries.size() == 1, "compiled android_wear_capabilities resource missing or duplicated");
        List<com.android.aapt.Resources.ConfigValue> configs = entries.get(0).getConfigValueList();
        require(configs.size() == 1, "compiled static capability configuration set differs");
        com.android.aapt.Resources.ConfigValue config = configs.get(0);
        require(config.hasConfig() && config.getConfig().equals(
            com.android.aapt.ConfigurationOuterClass.Configuration.getDefaultInstance()),
            "compiled static capability must use the unqualified default configuration");
        require(config.hasValue() && config.getValue().hasCompoundValue() &&
            config.getValue().getCompoundValue().hasArray(), "compiled static capability is not an array");
        List<com.android.aapt.Resources.Array.Element> elements =
            config.getValue().getCompoundValue().getArray().getElementList();
        require(elements.size() == 1 && elements.get(0).hasItem() && elements.get(0).getItem().hasStr() &&
            expectedCapability.equals(elements.get(0).getItem().getStr().getValue()),
            "compiled static capability set differs");
    }

    private static void verifyBundledFontLicenses(Path bundle) throws Exception {
        try (ZipFile zip = new ZipFile(bundle.toFile())) {
            var oflEntry = zip.getEntry("base/assets/licenses/geist-ofl.txt");
            var sourceEntry = zip.getEntry("base/assets/licenses/geist-source.txt");
            var appLicenseEntry = zip.getEntry("base/assets/licenses/healthmd-agpl-3.0.txt");
            require(oflEntry != null && sourceEntry != null, "bundled Geist license/source notice missing");
            require(appLicenseEntry != null, "Health.md AGPL license missing from independent Wear bundle");
            String ofl;
            String source;
            byte[] appLicenseBytes;
            try (InputStream input = zip.getInputStream(oflEntry)) {
                ofl = new String(input.readAllBytes(), StandardCharsets.UTF_8);
            }
            try (InputStream input = zip.getInputStream(sourceEntry)) {
                source = new String(input.readAllBytes(), StandardCharsets.UTF_8);
            }
            try (InputStream input = zip.getInputStream(appLicenseEntry)) {
                appLicenseBytes = input.readAllBytes();
            }
            require(ofl.contains("SIL OPEN FONT LICENSE Version 1.1"), "bundled Geist OFL text differs");
            require(source.contains("https://github.com/vercel/geist-font"), "bundled Geist source notice differs");
            String appLicenseSha256 = java.util.HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(appLicenseBytes)
            );
            require(HEALTHMD_AGPL_SHA256.equals(appLicenseSha256),
                "bundled Health.md AGPL text differs from the complete governing license");
        }
    }

    private static XmlElement readManifest(Path bundle, String formFactor) throws Exception {
        if (!Files.isRegularFile(bundle)) fail(formFactor + " AAB unavailable: " + bundle);
        XmlNode root;
        try (ZipFile zip = new ZipFile(bundle.toFile())) {
            var entry = zip.getEntry("base/manifest/AndroidManifest.xml");
            if (entry == null) fail(formFactor + " AAB has no base manifest");
            try (InputStream input = zip.getInputStream(entry)) { root = XmlNode.parseFrom(input); }
        }
        return root.getElement();
    }

    private static boolean meta(XmlElement parent, String name, String value) {
        return elements(parent, "meta-data").stream().anyMatch(e ->
            name.equals(attr(e, ANDROID, "name")) && value.equals(attr(e, ANDROID, "value")));
    }
    private static XmlElement one(XmlElement parent, String name) {
        List<XmlElement> found = elements(parent, name);
        require(found.size() == 1, "expected one " + name);
        return found.get(0);
    }
    private static List<XmlElement> elements(XmlElement parent, String name) {
        List<XmlElement> found = new ArrayList<>();
        for (XmlNode child : parent.getChildList()) if (child.hasElement() && name.equals(child.getElement().getName())) found.add(child.getElement());
        return found;
    }
    private static List<XmlElement> descendants(XmlElement parent, String name) {
        List<XmlElement> found = new ArrayList<>();
        for (XmlNode child : parent.getChildList()) if (child.hasElement()) {
            if (name.equals(child.getElement().getName())) found.add(child.getElement());
            found.addAll(descendants(child.getElement(), name));
        }
        return found;
    }
    private static String attr(XmlElement element, String name) { return attr(element, "", name); }
    private static String attr(XmlElement element, String namespace, String name) {
        for (XmlAttribute attr : element.getAttributeList()) if (namespace.equals(attr.getNamespaceUri()) && name.equals(attr.getName())) return attr.getValue();
        return "";
    }
    private static void require(boolean condition, String message) { if (!condition) fail(message); }
    private static void fail(String message) { System.err.println("Wear artifact validation failed: " + message); System.exit(1); }
}
