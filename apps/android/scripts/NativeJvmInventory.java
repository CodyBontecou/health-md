import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import java.util.TreeSet;
class NativeJvmInventory {
    public static void main(String[] args) throws Exception {
        Class<?> target = Class.forName(args[0], false, Thread.currentThread().getContextClassLoader());
        if (Arrays.stream(target.getAnnotations()).anyMatch(annotation -> annotation.annotationType().getName().equals("org.junit.runner.RunWith"))) {
            throw new IllegalStateException("Custom native JUnit runners require a reviewed discovery adapter");
        }
        TreeSet<String> names = new TreeSet<>();
        for (Method method : target.getMethods()) {
            if (Arrays.stream(method.getAnnotations()).anyMatch(annotation -> annotation.annotationType().getName().equals("org.junit.Test"))) {
                if (method.getParameterCount() != 0 || method.getReturnType() != void.class
                        || !Modifier.isPublic(method.getModifiers()) || Modifier.isStatic(method.getModifiers())
                        || method.getName().contains("*") || method.getName().contains("?")) {
                    throw new IllegalStateException("Native JUnit method cannot be selected exactly");
                }
                if (!names.add(method.getName())) throw new IllegalStateException("Duplicate JUnit method");
            }
        }
        if (names.isEmpty()) throw new IllegalStateException("Empty JUnit method inventory");
        for (String name : names) System.out.println(Base64.getEncoder().encodeToString(name.getBytes(StandardCharsets.UTF_8)));
    }
}
