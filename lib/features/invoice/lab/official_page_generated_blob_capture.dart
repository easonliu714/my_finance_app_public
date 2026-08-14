import 'dart:convert';

const String officialPageGeneratedBlobStoreKey =
    '__privateLabPageGeneratedBlobStore';
const String officialPageGeneratedBlobCaptureKey =
    '__privateLabPageGeneratedBlobCaptureInstalled';

/// Installs a bounded in-page Blob reference capture before the user presses
/// the official CSV button. Only Blob object references are retained briefly;
/// no bytes, URL, DOM, Cookie, or page content are returned to Dart here.
String buildOfficialPageGeneratedBlobCaptureScript({
  int maximumBytes = 10 * 1024 * 1024,
}) {
  final storeKey = jsonEncode(officialPageGeneratedBlobStoreKey);
  final captureKey = jsonEncode(officialPageGeneratedBlobCaptureKey);

  return '''
(() => {
  const storeKey = $storeKey;
  const captureKey = $captureKey;
  const maximumBytes = $maximumBytes;
  const retentionMs = 60000;

  const install = (target) => {
    try {
      if (!target || target[captureKey]) return;
      const nativeUrl = target.URL;
      if (!nativeUrl || typeof nativeUrl.createObjectURL !== 'function') return;

      const store = new Map();
      const originalCreateObjectURL = nativeUrl.createObjectURL.bind(nativeUrl);
      nativeUrl.createObjectURL = (object) => {
        const objectUrl = originalCreateObjectURL(object);
        try {
          if (object instanceof target.Blob &&
              object.size >= 0 && object.size <= maximumBytes) {
            store.set(objectUrl, object);
            target.setTimeout(() => store.delete(objectUrl), retentionMs);
          }
        } catch (_) {
          // Fail closed without changing the official download behavior.
        }
        return objectUrl;
      };
      Object.defineProperty(target, storeKey, {
        value: store,
        configurable: true,
      });
      Object.defineProperty(target, captureKey, {
        value: true,
        configurable: true,
      });
    } catch (_) {
      // A cross-origin or locked frame is intentionally ignored.
    }
  };

  const installTree = (target) => {
    install(target);
    try {
      for (let index = 0; index < target.frames.length; index += 1) {
        installTree(target.frames[index]);
      }
    } catch (_) {
      // Cross-origin frame contents remain inaccessible.
    }
  };

  installTree(window);
  if (!window.__privateLabBlobFrameObserver && document.documentElement) {
    const observer = new MutationObserver(() => installTree(window));
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
    });
    window.__privateLabBlobFrameObserver = observer;
    window.setTimeout(() => {
      try { observer.disconnect(); } catch (_) {}
      window.__privateLabBlobFrameObserver = null;
    }, retentionMs);
  }
  return 'PAGE_GENERATED_BLOB_CAPTURE_INSTALLED';
})()
''';
}

/// Returns JavaScript that resolves a previously captured Blob across the
/// current same-origin frame tree, then transfers it through the registered
/// Flutter handler. If no captured Blob exists, a same-context fetch fallback
/// is attempted for backward compatibility.
String buildOfficialPageGeneratedBlobReadScript({
  required Uri blobUri,
  required String handlerName,
  required String fileName,
  int maximumBytes = 10 * 1024 * 1024,
}) {
  final encodedBlobUrl = jsonEncode(blobUri.toString());
  final encodedHandler = jsonEncode(handlerName);
  final encodedFileName = jsonEncode(fileName);
  final storeKey = jsonEncode(officialPageGeneratedBlobStoreKey);

  return '''
(() => {
  const blobUrl = $encodedBlobUrl;
  const handler = $encodedHandler;
  const fileName = $encodedFileName;
  const storeKey = $storeKey;
  const maximumBytes = $maximumBytes;

  const findCapturedBlob = (target) => {
    try {
      const store = target[storeKey];
      if (store && typeof store.get === 'function') {
        const captured = store.get(blobUrl);
        if (captured) return captured;
      }
      for (let index = 0; index < target.frames.length; index += 1) {
        const nested = findCapturedBlob(target.frames[index]);
        if (nested) return nested;
      }
    } catch (_) {
      // Cross-origin frame contents remain inaccessible.
    }
    return null;
  };

  void (async () => {
    try {
      let blob = findCapturedBlob(window);
      if (!blob) {
        try {
          const response = await fetch(blobUrl);
          blob = await response.blob();
        } catch (_) {
          await window.flutter_inappwebview.callHandler(handler, {
            type: 'error', code: 'CSV_BLOB_NOT_CAPTURED'
          });
          return;
        }
      }
      if (!(blob instanceof Blob)) {
        await window.flutter_inappwebview.callHandler(handler, {
          type: 'error', code: 'CSV_BLOB_NOT_CAPTURED'
        });
        return;
      }
      if (blob.size > maximumBytes) {
        await window.flutter_inappwebview.callHandler(handler, {
          type: 'error', code: 'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED'
        });
        return;
      }

      const bytes = new Uint8Array(await blob.arrayBuffer());
      await window.flutter_inappwebview.callHandler(handler, {
        type: 'start', size: bytes.byteLength, fileName
      });
      const chunkSize = 65536;
      for (let offset = 0, index = 0;
           offset < bytes.length;
           offset += chunkSize, index += 1) {
        const chunk = bytes.subarray(
          offset,
          Math.min(offset + chunkSize, bytes.length),
        );
        let binary = '';
        for (let indexInChunk = 0;
             indexInChunk < chunk.length;
             indexInChunk += 1) {
          binary += String.fromCharCode(chunk[indexInChunk]);
        }
        await window.flutter_inappwebview.callHandler(handler, {
          type: 'chunk', index, base64: btoa(binary)
        });
      }
      await window.flutter_inappwebview.callHandler(handler, { type: 'end' });
    } catch (_) {
      await window.flutter_inappwebview.callHandler(handler, {
        type: 'error', code: 'CSV_BLOB_READ_FAILED'
      });
    }
  })();
  return 'CSV_BLOB_TRANSFER_ARMED';
})()
''';
}
