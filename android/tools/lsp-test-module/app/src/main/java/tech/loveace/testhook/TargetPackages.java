package tech.loveace.testhook;

import java.util.Collection;

final class TargetPackages {
    static final String PRODUCTION = "tech.loveace.appv3";

    private TargetPackages() {}

    static boolean isKnownVariant(String packageName) {
        if (packageName == null) return false;
        return packageName.equals(PRODUCTION) || packageName.startsWith(PRODUCTION + ".");
    }

    static boolean supportsProcess(String processName, Collection<String> scopedPackages) {
        if (processName == null) return false;
        for (String packageName : scopedPackages) {
            if (processName.equals(packageName) || processName.startsWith(packageName + ":")) {
                return true;
            }
        }
        return false;
    }

    static String packageFromProcess(String processName) {
        if (processName == null) return "";
        int separator = processName.indexOf(':');
        return separator < 0 ? processName : processName.substring(0, separator);
    }
}
