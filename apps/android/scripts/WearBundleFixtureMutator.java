import com.android.aapt.Resources;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Test-only protobuf mutator for adversarial packaged Wear/phone bundle fixtures. */
public final class WearBundleFixtureMutator {
    private static final String ANDROID = "http://schemas.android.com/apk/res/android";

    public static void main(String[] args) throws Exception {
        if (args.length < 4 || args.length > 5) {
            throw new IllegalArgumentException(
                "usage: WearBundleFixtureMutator <manifest|resources> input output mode [service]"
            );
        }
        Path input = Path.of(args[1]);
        Path output = Path.of(args[2]);
        if ("resources".equals(args[0])) {
            mutateResources(input, output, args[3]);
        } else if ("manifest".equals(args[0]) && args.length == 5) {
            mutateManifest(input, output, args[3], args[4]);
        } else {
            throw new IllegalArgumentException("invalid mutation arguments");
        }
    }

    private static void mutateResources(Path input, Path output, String mode) throws Exception {
        Resources.ResourceTable.Builder table;
        try (InputStream stream = Files.newInputStream(input)) {
            table = Resources.ResourceTable.parseFrom(stream).toBuilder();
        }
        Resources.Array.Builder array = null;
        outer:
        for (Resources.Package.Builder pkg : table.getPackageBuilderList()) {
            for (Resources.Type.Builder type : pkg.getTypeBuilderList()) {
                if (!"array".equals(type.getName())) continue;
                for (Resources.Entry.Builder entry : type.getEntryBuilderList()) {
                    if (!"android_wear_capabilities".equals(entry.getName())) continue;
                    array = entry.getConfigValueBuilder(0).getValueBuilder()
                        .getCompoundValueBuilder().getArrayBuilder();
                    break outer;
                }
            }
        }
        if (array == null || array.getElementCount() != 1) {
            throw new IllegalStateException("capability array unavailable");
        }
        switch (mode) {
            case "extra-capability" -> array.addElement(array.getElement(0));
            case "qualified-capability" -> qualifyCapability(table);
            case "reference-capability" -> array.getElementBuilder(0).setItem(
                Resources.Item.newBuilder().setRef(
                    Resources.Reference.newBuilder().setName("string/not_a_static_capability")
                )
            );
            default -> throw new IllegalArgumentException("unknown resource mutation: " + mode);
        }
        try (OutputStream stream = Files.newOutputStream(output)) {
            table.build().writeTo(stream);
        }
    }

    private static void qualifyCapability(Resources.ResourceTable.Builder table) {
        for (Resources.Package.Builder pkg : table.getPackageBuilderList()) {
            for (Resources.Type.Builder type : pkg.getTypeBuilderList()) {
                if (!"array".equals(type.getName())) continue;
                for (Resources.Entry.Builder entry : type.getEntryBuilderList()) {
                    if ("android_wear_capabilities".equals(entry.getName())) {
                        entry.getConfigValueBuilder(0).getConfigBuilder().setLocale("fr");
                        return;
                    }
                }
            }
        }
        throw new IllegalStateException("capability config unavailable");
    }

    private static void mutateManifest(
        Path input,
        Path output,
        String mode,
        String expectedService
    ) throws Exception {
        Resources.XmlNode.Builder root;
        try (InputStream stream = Files.newInputStream(input)) {
            root = Resources.XmlNode.parseFrom(stream).toBuilder();
        }
        Resources.XmlElement.Builder manifest = root.getElementBuilder();
        Resources.XmlElement.Builder application = children(manifest, "application").stream()
            .findFirst().orElseThrow(() -> new IllegalStateException("application unavailable"));
        Resources.XmlElement.Builder service = children(application, "service").stream()
            .filter(element -> expectedService.equals(attribute(element, "name")))
            .findFirst().orElseThrow(() -> new IllegalStateException("service unavailable"));
        List<Resources.XmlElement.Builder> filters = children(service, "intent-filter");
        switch (mode) {
            case "duplicate-service" -> application.addChild(
                Resources.XmlNode.newBuilder().setElement(service.build())
            );
            case "duplicate-other-service", "duplicate-other-action" -> {
                Resources.XmlElement.Builder copy = service.build().toBuilder();
                setAttribute(copy, "name", expectedService + "Unexpected");
                if ("duplicate-other-action".equals(mode)) {
                    for (Resources.XmlElement.Builder filter : children(copy, "intent-filter")) {
                        for (Resources.XmlElement.Builder action : children(filter, "action")) {
                            setAttribute(action, "name", "com.google.android.gms.wearable.CHANNEL_EVENT");
                        }
                    }
                }
                application.addChild(Resources.XmlNode.newBuilder().setElement(copy));
            }
            case "extra-filter" -> {
                if (filters.isEmpty()) throw new IllegalStateException("filter unavailable");
                service.addChild(Resources.XmlNode.newBuilder().setElement(filters.get(0).build()));
            }
            case "combine-actions" -> {
                if (filters.size() != 2) throw new IllegalStateException("two filters required");
                Resources.XmlNode firstAction = childNodes(filters.get(0), "action").get(0).build();
                Resources.XmlNode secondAction = childNodes(filters.get(1), "action").get(0).build();
                filters.get(0).addChild(secondAction);
                filters.get(1).addChild(firstAction);
            }
            default -> throw new IllegalArgumentException("unknown manifest mutation: " + mode);
        }
        try (OutputStream stream = Files.newOutputStream(output)) {
            root.build().writeTo(stream);
        }
    }

    private static List<Resources.XmlElement.Builder> children(
        Resources.XmlElement.Builder parent,
        String name
    ) {
        List<Resources.XmlElement.Builder> found = new ArrayList<>();
        for (Resources.XmlNode.Builder child : parent.getChildBuilderList()) {
            if (child.hasElement() && name.equals(child.getElement().getName())) {
                found.add(child.getElementBuilder());
            }
        }
        return found;
    }

    private static List<Resources.XmlNode.Builder> childNodes(
        Resources.XmlElement.Builder parent,
        String name
    ) {
        List<Resources.XmlNode.Builder> found = new ArrayList<>();
        for (Resources.XmlNode.Builder child : parent.getChildBuilderList()) {
            if (child.hasElement() && name.equals(child.getElement().getName())) found.add(child);
        }
        return found;
    }

    private static void setAttribute(
        Resources.XmlElement.Builder element,
        String name,
        String value
    ) {
        for (Resources.XmlAttribute.Builder attribute : element.getAttributeBuilderList()) {
            if (ANDROID.equals(attribute.getNamespaceUri()) && name.equals(attribute.getName())) {
                attribute.setValue(value);
                if (attribute.hasCompiledItem()) attribute.clearCompiledItem();
                return;
            }
        }
        throw new IllegalStateException("attribute unavailable: " + name);
    }

    private static String attribute(Resources.XmlElement.Builder element, String name) {
        return element.getAttributeList().stream()
            .filter(attribute -> ANDROID.equals(attribute.getNamespaceUri()) && name.equals(attribute.getName()))
            .map(Resources.XmlAttribute::getValue)
            .findFirst().orElse("");
    }
}
