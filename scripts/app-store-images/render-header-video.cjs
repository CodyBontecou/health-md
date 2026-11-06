#!/usr/bin/env node
// Deterministic Canvas capture. Requires Playwright, sharp, Chrome, ffmpeg and ffprobe.
const fs=require('node:fs');
const path=require('node:path');
const {spawn,execFileSync}=require('node:child_process');
const {once}=require('node:events');
const {pathToFileURL}=require('node:url');
function dependency(name){
 try{return require(name)}catch{}
 if(process.env.HEADER_NODE_MODULES)return require(path.join(process.env.HEADER_NODE_MODULES,name));
 throw new Error(`Cannot load ${name}. Set HEADER_NODE_MODULES to a directory containing playwright and sharp.`);
}
const {chromium}=dependency('playwright'),sharp=dependency('sharp');
const root=path.resolve(__dirname,'../..');
const output=path.resolve(process.argv[2]||path.join(root,'app-store-output/header-video'));
const FPS=30,DURATION=12,WIDTH=3840,HEIGHT=1646;
async function main(){
 fs.mkdirSync(output,{recursive:true});
 const source=path.join(root,'apps/apple/HealthMd/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png');
 const {data,info}=await sharp(source).extract({left:225,top:230,width:590,height:592}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 // The icon has a solid black background. Remove only neutral near-black pixels.
 for(let i=0;i<data.length;i+=4){const peak=Math.max(data[i],data[i+1],data[i+2]);data[i+3]=Math.round(Math.max(0,Math.min(1,(peak-8)/18))*255)}
 const icon=await sharp(data,{raw:info}).png().toBuffer();
 const template=fs.readFileSync(path.join(__dirname,'header-video.html'),'utf8');
 const html=template.replace('__HEART_DATA__',`data:image/png;base64,${icon.toString('base64')}`);
 const preview=path.join(output,'healthmd-header.html');fs.writeFileSync(preview,html);
 const browser=await chromium.launch({executablePath:process.env.HEADER_CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--allow-file-access-from-files']});
 try{
  const page=await browser.newPage({viewport:{width:WIDTH,height:HEIGHT},deviceScaleFactor:1});
  await page.goto(pathToFileURL(preview).href+'?capture');await page.evaluate(()=>window.ready);
  await page.evaluate(()=>renderAt(3));await page.screenshot({path:path.join(output,'healthmd-header-poster.png')});
  const sampleTimes=[0,.4,1.5,3,5,7.5,9,11.6,12];
  const samples=[];
  for(const time of sampleTimes){await page.evaluate(t=>renderAt(t),time);samples.push(await page.screenshot())}
  const thumbW=640,thumbH=274;
  await sharp({create:{width:thumbW*3,height:thumbH*3,channels:3,background:'#07050e'}}).composite(await Promise.all(samples.map(async(input,i)=>({input:await sharp(input).resize(thumbW,thumbH).png().toBuffer(),left:i%3*thumbW,top:Math.floor(i/3)*thumbH})))).png().toFile(path.join(output,'contact-sheet.png'));
  const seam=Buffer.compare(samples[0],samples[samples.length-1])===0;
  if(!seam)throw new Error('Frame 0 and frame 12 do not match');
  console.log('Poster, contact sheet and exact loop seam verified.');
  if(process.env.HEADER_STILL_ONLY==='1')return;
  const video=path.join(output,'healthmd-app-store-header.mp4');
  const encoder=spawn('ffmpeg',['-y','-v','error','-f','image2pipe','-framerate',String(FPS),'-vcodec','mjpeg','-i','pipe:0','-an','-c:v','libx264','-preset','medium','-crf','16','-pix_fmt','yuv420p','-r',String(FPS),'-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-movflags','+faststart',video],{stdio:['pipe','inherit','inherit']});
  let encoderError;encoder.on('error',error=>{encoderError=error});
  const completed=once(encoder,'close');
  for(let i=0;i<FPS*DURATION;i++){
   await page.evaluate(t=>renderAt(t),i/FPS);
   const frame=await page.screenshot({type:'jpeg',quality:97});
   if(!encoder.stdin.write(frame))await once(encoder.stdin,'drain');
   if(encoderError)throw encoderError;
   if(i%60===0)console.log(`Rendered ${i}/${FPS*DURATION} frames`);
  }
  encoder.stdin.end();const [code]=await completed;if(code!==0)throw new Error(`ffmpeg exited ${code}`);
  const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',video],{encoding:'utf8'}));
  const stream=probe.streams.find(s=>s.codec_type==='video');
  if(stream.width!==WIDTH||stream.height!==HEIGHT||stream.avg_frame_rate!=='30/1'||Math.abs(Number(probe.format.duration)-DURATION)>.001)throw new Error('Encoded video specifications mismatch');
  fs.writeFileSync(path.join(output,'verification.json'),JSON.stringify({concept:'Amethyst pulse',duration:DURATION,width:WIDTH,height:HEIGHT,fps:FPS,seamExact:seam,sourceArtwork:path.relative(root,source),video:probe},null,2)+'\n');
  console.log(`Verified ${video}: ${WIDTH}×${HEIGHT}, ${FPS} fps, ${DURATION}s; ${probe.format.size} bytes.`);
 }finally{await browser.close()}
}
main().catch(error=>{console.error(error);process.exitCode=1});
