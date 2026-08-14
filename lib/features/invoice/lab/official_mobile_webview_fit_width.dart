String buildOfficialMobileFitWidthScript() {
  return '''
(() => {
  try {
    const root = document.documentElement;
    const body = document.body;
    if (!root || !body) return 'FIT_WIDTH_SKIPPED';
    body.style.zoom = '';
    const viewportWidth = Math.max(root.clientWidth, window.innerWidth || 0);
    const contentWidth = Math.max(root.scrollWidth, body.scrollWidth);
    if (viewportWidth <= 0 || contentWidth <= viewportWidth) {
      return 'FIT_WIDTH_NOT_REQUIRED';
    }
    const scale = Math.max(0.72, Math.min(1, viewportWidth / contentWidth));
    body.style.transformOrigin = 'top left';
    body.style.zoom = String(scale);
    body.dataset.privateLabFitWidth = String(scale);
    return 'FIT_WIDTH_APPLIED';
  } catch (_) {
    return 'FIT_WIDTH_FAILED';
  }
})()
''';
}
