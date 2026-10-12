const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {gzipSync} = require('node:zlib');
const {webcrypto, createHash} = require('node:crypto');
const source = fs.readFileSync('web/review/model-download.js','utf8');
const raw = Buffer.from('a verified source model');
const packed = gzipSync(raw);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const manifest = {models:{row:{bytes:raw.length,compressedBytes:packed.length,
  sha256:hash(raw),compressedSha256:hash(packed),bundled:false}}};
function fixture(download) {
  const window = {};
  let requests = 0;
  vm.runInNewContext(source, {window, caches:{open:async()=>{throw Error('unavailable');}},
    fetch:async(url,options)=>{
      if(url.includes('manifest')) return new Response(JSON.stringify(manifest));
      requests++; return download(options);
    },crypto:webcrypto,URL,Blob,Response,Uint8Array,DecompressionStream,DOMException,
    AbortController,setTimeout,clearTimeout,location:{href:'http://localhost/exercise-review.html'}});
  return {delivery:window.PulseModelDelivery, requests:()=>requests};
}
test('review downloader verifies decompression when browser cache is unavailable',async()=>{
  const f=fixture(()=>new Response(packed));
  const progress=[];
  const result=await f.delivery.resolve('row',{progress:(n,total)=>progress.push([n,total])});
  assert(result.src.startsWith('blob:'));
  assert.equal(f.requests(),1);
  assert.deepEqual(progress.at(-1),[packed.length,packed.length]);
  result.release();
});
test('review downloader rejects a corrupt compressed source',async()=>{
  const corrupt=Buffer.from(packed);corrupt[15]^=1;
  const f=fixture(()=>new Response(corrupt));
  await assert.rejects(f.delivery.resolve('row'),/完整性校验失败/);
});
test('review downloader aborts a trickling body at its total deadline',async()=>{
  let aborted=false;
  const f=fixture(({signal})=>new Response(new ReadableStream({
    start(controller) {
      const interval=setInterval(()=>controller.enqueue(Uint8Array.of(0)),10);
      signal.addEventListener('abort',()=>{
        aborted=true;clearInterval(interval);
        controller.error(new DOMException('Aborted','AbortError'));
      },{once:true});
    }
  })));
  await assert.rejects(f.delivery.resolve('row',{timeoutMs:60}),/下载超时/);
  assert.equal(aborted,true);
});
