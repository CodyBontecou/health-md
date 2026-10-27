package com.healthmd.ci;

import android.database.Cursor;
import android.database.MatrixCursor;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

/** SAF fixture in the isolated E2E app's private cache; absent from debug and release apps. */
public final class CIExportDocumentsProvider extends DocumentsProvider {
    private static final String[] COLUMNS = {Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS, Document.COLUMN_SIZE};
    @Override public boolean onCreate() { return true; }
    private File file(String id) throws FileNotFoundException {
        try {
            String rootId = id.split("/", 2)[0];
            if (!rootId.matches("ci-[a-zA-Z0-9-]+")) throw new IllegalArgumentException("Invalid fixture root");
            File root = new File(getContext().getCacheDir(), "ci-export/" + rootId).getCanonicalFile();
            File target = id.contains("/") ? new File(root, id.substring(id.indexOf('/') + 1)).getCanonicalFile() : root;
            if (!target.toPath().startsWith(root.toPath())) throw new IllegalArgumentException("Invalid fixture path");
            if (target.equals(root)) root.mkdirs();
            return target;
        } catch (IOException e) { throw new FileNotFoundException("Fixture path unavailable"); }
    }
    private void add(MatrixCursor cursor, String[] columns, String id, File target) {
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String c : columns) {
            Object value = null;
            if (Document.COLUMN_DOCUMENT_ID.equals(c)) value = id;
            else if (Document.COLUMN_DISPLAY_NAME.equals(c)) value = id.contains("/") ? target.getName() : "CI export";
            else if (Document.COLUMN_MIME_TYPE.equals(c)) value = target.isDirectory() ? Document.MIME_TYPE_DIR : "text/markdown";
            else if (Document.COLUMN_FLAGS.equals(c)) value = Document.FLAG_SUPPORTS_WRITE | Document.FLAG_SUPPORTS_DELETE | (target.isDirectory() ? Document.FLAG_DIR_SUPPORTS_CREATE : 0);
            else if (Document.COLUMN_SIZE.equals(c)) value = target.length();
            row.add(value);
        }
    }
    @Override public Cursor queryRoots(String[] projection) {
        String[] columns = projection != null ? projection : new String[]{Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_FLAGS};
        MatrixCursor cursor = new MatrixCursor(columns);
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String c : columns) row.add(Root.COLUMN_ROOT_ID.equals(c) || Root.COLUMN_DOCUMENT_ID.equals(c) ? "ci-default" : Root.COLUMN_TITLE.equals(c) ? "Synthetic CI destination" : Root.COLUMN_FLAGS.equals(c) ? Root.FLAG_SUPPORTS_CREATE : null);
        return cursor;
    }
    @Override public Cursor queryDocument(String id, String[] projection) throws FileNotFoundException {
        String[] columns = projection != null ? projection : COLUMNS;
        MatrixCursor cursor = new MatrixCursor(columns); add(cursor, columns, id, file(id)); return cursor;
    }
    @Override public Cursor queryChildDocuments(String id, String[] projection, String sort) throws FileNotFoundException {
        String[] columns = projection != null ? projection : COLUMNS;
        MatrixCursor cursor = new MatrixCursor(columns);
        File[] children = file(id).listFiles();
        if (children != null) for (File child : children) add(cursor, columns, id + "/" + child.getName(), child);
        return cursor;
    }
    @Override public String createDocument(String parent, String mime, String name) throws FileNotFoundException {
        if (name.isEmpty() || name.equals(".") || name.equals("..") || name.contains("/") || name.contains("\\")) throw new IllegalArgumentException("Invalid fixture name");
        String id = parent + "/" + name;
        try {
            File target = file(id);
            if (!(Document.MIME_TYPE_DIR.equals(mime) ? target.mkdir() : target.createNewFile())) throw new FileNotFoundException("Fixture create failed");
        } catch (IOException e) { throw new FileNotFoundException("Fixture create failed"); }
        return id;
    }
    @Override public ParcelFileDescriptor openDocument(String id, String mode, CancellationSignal signal) throws FileNotFoundException { return ParcelFileDescriptor.open(file(id), ParcelFileDescriptor.parseMode(mode)); }
    private void remove(File f) throws FileNotFoundException {
        File[] children = f.listFiles();
        if (children != null) for (File child : children) remove(child);
        if (!f.delete()) throw new FileNotFoundException("Fixture delete failed");
    }
    @Override public void deleteDocument(String id) throws FileNotFoundException { remove(file(id)); }
    @Override public boolean isChildDocument(String parent, String id) {
        try { return file(id).toPath().startsWith(file(parent).toPath()); }
        catch (FileNotFoundException e) { return false; }
    }
}
