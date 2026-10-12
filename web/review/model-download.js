/* Lossless verified delivery for the existing standalone review pages. */
(function(root) {
  let manifest;
  const cacheName = 'pulse-model-v1';
  root.PulseModelDelivery = {
    async resolve(id, {signal: externalSignal, progress = () => {}, timeoutMs = 180000} = {}) {
      const control = new AbortController();
      const signal = control.signal;
      const cancel = () => control.abort();
      if (externalSignal?.aborted) cancel();
      externalSignal?.addEventListener('abort', cancel, {once:true});
      let expired = false;
      const deadline = setTimeout(() => {expired = true; control.abort();}, timeoutMs);
      try {
      manifest ||= await fetch('assets/assets/muscles/model_manifest.json', {signal}).then(r => {
        if (!r.ok) throw new Error('动作资源目录载入失败。');
        return r.json();
      });
      const entry = manifest.models[id];
      if (!entry) throw new Error('动作资源未准备好。');
      if (entry.bundled) return {src: `assets/assets/models/athlete_${id}.glb`, release() {}};
      const key = new URL(`__pulse_model_cache__/${id}-${entry.sha256}.glb`, location.href).href;
      let cache;
      try {cache = await caches.open(cacheName);} catch (_) { /* Playback can work without persistent cache. */ }
      let response;
      try {response = await cache?.match(key);} catch (_) { /* Cache is optional. */ }
      const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)))
          .map(v => v.toString(16).padStart(2, '0')).join('');
      let raw;
      if (response) {
        const bytes = await response.arrayBuffer();
        if (bytes.byteLength === entry.bytes && await hash(bytes) === entry.sha256) raw = bytes;
        else {try {await cache.delete(key);} catch (_) { /* Retry verified bytes. */ }}
      }
      if (!raw) {
        response = await fetch(`remote/models/athlete_${id}.glb.gz`, {signal});
        if (!response.ok) throw new Error('动作下载失败，请重试。');
        const reader = response.body.getReader();
        const chunks = []; let received = 0;
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          chunks.push(value); received += value.byteLength;
          if (received > entry.compressedBytes) {await reader.cancel(); throw new Error('下载文件大小不符。');}
          progress(received, entry.compressedBytes);
        }
        const packed = await new Blob(chunks).arrayBuffer();
        if (packed.byteLength !== entry.compressedBytes || await hash(packed) !== entry.compressedSha256) {
          throw new Error('动作下载完整性校验失败。');
        }
        raw = await new Response(new Blob([packed]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
        if (raw.byteLength !== entry.bytes || await hash(raw) !== entry.sha256) throw new Error('模型完整性校验失败。');
        if (signal?.aborted) throw new DOMException('Cancelled', 'AbortError');
        try {await cache?.put(key, new Response(raw));} catch (_) { /* Cache quota must not prevent this preview. */ }
      }
      if (signal?.aborted) throw new DOMException('Cancelled', 'AbortError');
      const src = URL.createObjectURL(new Blob([raw], {type:'model/gltf-binary'}));
      return {src, release() {URL.revokeObjectURL(src);}};
      } catch (error) {
        if (expired) throw new Error('动作下载超时，请先看轻量视频后重试。');
        throw error;
      } finally {
        clearTimeout(deadline);
        externalSignal?.removeEventListener('abort', cancel);
      }
    }
  };
})(window);
