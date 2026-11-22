package dev.flutterbird.ladybird;

import android.content.Context;
import android.content.res.AssetManager;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

final class LadybirdRuntimeFiles {
    static final class RuntimeConfiguration {
        final String resourceRoot;
        final String userDir;
        final String nativeLibraryDir;
        final String certificatesPath;

        RuntimeConfiguration(
                String resourceRoot,
                String userDir,
                String nativeLibraryDir,
                String certificatesPath
        ) {
            this.resourceRoot = resourceRoot;
            this.userDir = userDir;
            this.nativeLibraryDir = nativeLibraryDir;
            this.certificatesPath = certificatesPath;
        }
    }

    private LadybirdRuntimeFiles() {
    }

    static RuntimeConfiguration prepare(Context context) throws IOException {
        Context appContext = context.getApplicationContext();
        File runtimeRoot = new File(appContext.getFilesDir(), "ladybird-runtime");
        File resourceRoot = new File(runtimeRoot, "resource-root");
        File userDir = new File(runtimeRoot, "user");
        File certificatesFile = new File(resourceRoot, "cacert.pem");

        ensureDirectory(runtimeRoot);
        ensureDirectory(resourceRoot);
        ensureDirectory(userDir);
        ensureDirectory(new File(userDir, "config"));
        ensureDirectory(new File(userDir, "userdata"));
        ensureDirectory(new File(userDir, "runtime"));
        ensureDirectory(new File(userDir, "cache"));

        // The copy on disk has to be the one this build of the app ships. A file
        // check alone kept the first copy ever extracted forever, so a Ladybird
        // update that added pages (about:settings and the like) left them missing
        // and the engine died looking for them. Tie the copy to the installed app
        // instead: every install or update of the app extracts it afresh.
        File sentinel = new File(resourceRoot, "icons/48x48/app-browser.png");
        File stamp = new File(resourceRoot, ".assets-stamp");
        String expectedStamp = assetsStamp(appContext);
        if (!sentinel.exists() || !expectedStamp.equals(readText(stamp))) {
            deleteContents(resourceRoot, certificatesFile);
            extractZipAsset(appContext.getAssets(), "ladybird-assets.zip", resourceRoot);
            writeText(stamp, expectedStamp);
        }

        if (!certificatesFile.exists() || certificatesFile.length() == 0L) {
            writeCertificatesBundle(certificatesFile);
        }

        return new RuntimeConfiguration(
                resourceRoot.getAbsolutePath(),
                userDir.getAbsolutePath(),
                appContext.getApplicationInfo().nativeLibraryDir,
                certificatesFile.getAbsolutePath());
    }

    private static void extractZipAsset(AssetManager assetManager, String assetName, File targetDir)
            throws IOException {
        String rootPath = targetDir.getCanonicalPath() + File.separator;
        try (InputStream inputStream = assetManager.open(assetName);
             ZipInputStream zipInputStream = new ZipInputStream(inputStream)) {
            ZipEntry entry;
            while ((entry = zipInputStream.getNextEntry()) != null) {
                File outputFile = new File(targetDir, entry.getName());
                String outputPath = outputFile.getCanonicalPath();
                if (!outputPath.startsWith(rootPath)) {
                    throw new IOException("Refusing to extract asset outside target directory: " + entry.getName());
                }

                if (entry.isDirectory()) {
                    ensureDirectory(outputFile);
                    continue;
                }

                File parent = outputFile.getParentFile();
                if (parent != null) {
                    ensureDirectory(parent);
                }

                try (OutputStream outputStream = new FileOutputStream(outputFile)) {
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = zipInputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, read);
                    }
                }
            }
        }
    }

    private static void writeCertificatesBundle(File targetFile) throws IOException {
        File certDirectory = new File("/system/etc/security/cacerts");
        File[] certificateFiles = certDirectory.listFiles();
        if (certificateFiles == null) {
            throw new IOException("Unable to enumerate Android system certificates");
        }

        try (OutputStream outputStream = new FileOutputStream(targetFile, false)) {
            byte[] buffer = new byte[8192];
            for (File certificateFile : certificateFiles) {
                if (certificateFile == null || !certificateFile.isFile()) {
                    continue;
                }

                try (InputStream inputStream = java.nio.file.Files.newInputStream(certificateFile.toPath())) {
                    int read;
                    while ((read = inputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, read);
                    }
                }
            }
        }
    }

    // Changes whenever the app is installed or updated.
    private static String assetsStamp(Context context) {
        try {
            android.content.pm.PackageInfo info = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0);
            return info.lastUpdateTime + ":" + info.versionName;
        } catch (android.content.pm.PackageManager.NameNotFoundException exception) {
            // Without it every launch extracts afresh, which is slow but right.
            return "unknown:" + System.nanoTime();
        }
    }

    private static String readText(File file) {
        try {
            return new String(java.nio.file.Files.readAllBytes(file.toPath()),
                    java.nio.charset.StandardCharsets.UTF_8);
        } catch (IOException exception) {
            return "";
        }
    }

    private static void writeText(File file, String text) throws IOException {
        java.nio.file.Files.write(file.toPath(), text.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    // Empties a directory, apart from one file to keep, so that a file the new
    // copy no longer has does not linger from the old one.
    private static void deleteContents(File directory, File keep) throws IOException {
        File[] children = directory.listFiles();
        if (children == null) {
            return;
        }
        for (File child : children) {
            if (child.equals(keep)) {
                continue;
            }
            if (child.isDirectory()) {
                deleteContents(child, null);
            }
            if (!child.delete() && child.exists()) {
                throw new IOException("Unable to delete: " + child);
            }
        }
    }

    private static void ensureDirectory(File directory) throws IOException {
        if (directory.isDirectory()) {
            return;
        }
        if (!directory.mkdirs() && !directory.isDirectory()) {
            throw new IOException("Unable to create directory: " + directory);
        }
    }
}