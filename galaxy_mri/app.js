/* Galaxy Traveling-Subject MRI: charts and interactions (no libraries) */
(function(){
const NS="http://www.w3.org/2000/svg";
const STYLE_ATTRS=["fill","stroke","opacity","fill-opacity"];
function el(tag,attrs,parent,text){const e=document.createElementNS(NS,tag);let st="";
  for(const k in attrs){const v=attrs[k];if(STYLE_ATTRS.includes(k)&&typeof v==="string"&&v.indexOf("var(")===0){st+=k+":"+v+";"}else e.setAttribute(k,v)}
  if(st)e.setAttribute("style",st);if(text!=null)e.textContent=text;if(parent)parent.appendChild(e);return e}
function clear(s){while(s.firstChild)s.removeChild(s.firstChild)}
function seg(container,items,initial,onChange){const c=document.getElementById(container);c.innerHTML="";const btns=items.map(it=>{const b=document.createElement("button");b.type="button";b.textContent=it.label;b.setAttribute("aria-pressed",it.key===initial?"true":"false");b.addEventListener("click",()=>{btns.forEach(x=>x.setAttribute("aria-pressed","false"));b.setAttribute("aria-pressed","true");onChange(it.key)});c.appendChild(b);return b});}

const SITES=["Tatooine","Hoth","Endor","Naboo","Dagobah","Bespin"];
const PEOPLE=["Leia","Luke","Han"];

/* ---------- hero diagram ---------- */
(function hero(){
  const s=document.getElementById("heroSvg");
  const cx=210,cy=150,R=118;
  const pos=SITES.map((n,i)=>{const a=-Math.PI/2+i*2*Math.PI/6;return[cx+R*Math.cos(a),cy+R*Math.sin(a)]});
  pos.forEach(p=>el("line",{x1:cx,y1:cy,x2:p[0],y2:p[1],stroke:"var(--line)","stroke-width":1.5,"stroke-dasharray":"4 4"},s));
  el("circle",{cx,cy,r:34,fill:"var(--accent-soft)",stroke:"var(--accent)","stroke-width":1.5},s);
  ["Leia","Luke","Han"].forEach((n,i)=>el("text",{x:cx,y:cy-12+i*14,"text-anchor":"middle","font-size":"11"},s,n));
  pos.forEach((p,i)=>{
    const g=el("g",{},s);
    el("rect",{x:p[0]-42,y:p[1]-16,width:84,height:32,rx:16,fill:"var(--surface)",stroke:"var(--line)"},g);
    el("circle",{cx:p[0]-28,cy:p[1],r:7,fill:"none",stroke:"var(--accent)","stroke-width":3},g);
    el("text",{x:p[0]-17,y:p[1]+4,"text-anchor":"start","font-size":"10"},g,SITES[i]);
  });
})();


/* ---------- abstract route ---------- */
(function route(){
  const s=document.getElementById("routeSvg");if(!s)return;
  const d="M 150 250 C 95 250 55 205 70 160 C 85 112 130 105 165 92 C 215 74 255 48 330 46 C 410 44 470 62 520 52 C 580 40 640 70 638 130 C 636 185 600 205 585 235 C 565 275 500 288 430 282 C 360 276 300 262 240 262 C 205 262 185 250 150 250 Z";
  el("path",{d,fill:"none",stroke:"var(--line)","stroke-width":10,"stroke-linecap":"round"},s);
  const p=el("path",{d,fill:"none",stroke:"var(--accent)","stroke-width":2.5,"stroke-dasharray":"7 6"},s);
  const L=p.getTotalLength();
  const STOPS=[["Endor",0,"home base"],["Hoth",.07],["Dagobah",.15],[null,.22],[null,.31],[null,.40],[null,.47],[null,.55],["Naboo",.63],["Bespin",.74],["Tatooine",.80],[null,.89]];
  const pts=STOPS.map(st=>{const q=p.getPointAtLength(st[1]*L);return{x:q.x,y:q.y,name:st[0],note:st[2]}});
  const cx=360,cy=160;
  pts.forEach((q,i)=>{
    const dx=q.x-cx,dy=q.y-cy,n=Math.hypot(dx,dy)||1,ox=dx/n,oy=dy/n;
    if(q.name){
      el("circle",{cx:q.x,cy:q.y,r:i===0?13:10,fill:"var(--accent)",stroke:"var(--surface)","stroke-width":3},s);
      const tx=q.x+ox*26,ty=q.y+oy*24+4;
      el("text",{x:tx,y:ty,"text-anchor":ox>0.35?"start":(ox<-0.35?"end":"middle"),"font-size":"12","font-weight":"600"},s,q.name+(q.note?" ("+q.note+")":""));
    }else{
      el("circle",{cx:q.x,cy:q.y,r:5.5,fill:"var(--surface)",stroke:"var(--muted)","stroke-width":2},s);
    }
    el("text",{x:q.x-ox*16,y:q.y-oy*16+3,"text-anchor":"middle",class:"tick"},s,String(i+1));
  });
  const rv=el("g",{},s);
  el("rect",{x:-11,y:-7,width:22,height:14,rx:4,fill:"var(--accent2)",stroke:"var(--surface)","stroke-width":2},rv);
  el("rect",{x:3,y:-4,width:6,height:5,rx:1,fill:"var(--surface)"},rv);
  const place=f=>{const q=p.getPointAtLength(((f%1)+1)%1*L);rv.setAttribute("transform",`translate(${q.x},${q.y})`)};
  place(0);
  const label=document.getElementById("driveStop");
  const nearest=f=>{let best=null;for(let i=0;i<STOPS.length;i++){const sf=STOPS[i][1];if(Math.abs(f-sf)<0.012||Math.abs(f-1-sf)<0.012)best=i}return best};
  let raf=null;
  document.getElementById("driveBtn").addEventListener("click",()=>{
    const reduce=window.matchMedia&&window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if(raf)cancelAnimationFrame(raf);
    if(reduce){place(0);label.textContent="12 stops, back at Endor";return}
    const t0=performance.now(),dur=12000;
    const step=t=>{const f=Math.min(1,(t-t0)/dur);place(f);const k=nearest(f);
      if(k!=null)label.textContent=`Stop ${k+1}: `+(STOPS[k][0]||"other stop");
      if(f<1)raf=requestAnimationFrame(step);else{raf=null;label.textContent="Back at Endor. Twelve stops, one loop."}};
    raf=requestAnimationFrame(step);
  });
})();

/* ---------- design matrix ---------- */
const AVAIL={
  t1:{label:"T1 anatomy",has:()=>true,note:"All 18 sessions have a T1-weighted scan."},
  rest:{label:"Resting state",has:()=>true,note:"All 18 sessions have an 8-minute resting-state run."},
  stroop:{label:"Stroop",has:(s)=>["Hoth","Endor","Bespin"].includes(s),note:"9 usable Stroop runs. Tatooine and Dagobah have no task data; Naboo's Stroop logs were lost, and the trial order was randomized per session, so its runs can't be modelled."},
  food:{label:"Food cues",has:(s,p)=>["Hoth","Endor","Naboo","Bespin"].includes(s),partial:(s,p)=>s==="Bespin"&&p==="Leia",note:"12 food-cue runs. Leia's Bespin run ends early (528 s of the archive survived)."}
};
function drawDesign(key){
  const s=document.getElementById("designSvg");clear(s);
  const L=90,T=30,cw=88,ch=48;
  SITES.forEach((n,i)=>el("text",{x:L+i*cw+cw/2,y:20,"text-anchor":"middle"},s,n));
  PEOPLE.forEach((p,j)=>{el("text",{x:L-10,y:T+j*ch+ch/2+4,"text-anchor":"end","font-size":"12"},s,p);
    SITES.forEach((n,i)=>{const a=AVAIL[key];const has=a.has(n,p);const part=a.partial&&a.partial(n,p);
      el("rect",{x:L+i*cw+4,y:T+j*ch+4,width:cw-8,height:ch-8,rx:6,fill:has?(part?"var(--accent2-soft)":"var(--accent-soft)"):"var(--soft)",stroke:has?(part?"var(--accent2)":"var(--accent)"):"var(--line)"},s);
      el("text",{x:L+i*cw+cw/2,y:T+j*ch+ch/2+4,"text-anchor":"middle",fill:has?"var(--ink)":"var(--muted)"},s,has?(part?"partial":"✓"):"none");
    })});
  document.getElementById("designNote").textContent=AVAIL[key].note;
}
seg("modSeg",Object.keys(AVAIL).map(k=>({key:k,label:AVAIL[k].label})),"t1",drawDesign);drawDesign("t1");

const SITEINFO=[["Tatooine","GE","Inversion-recovery FSPGR, 1.2 mm slices",3.77,3.17],["Hoth","GE","Reconstructed to 0.5 mm slices by interpolation",3.17,3.85],["Endor","Siemens","MPRAGE",2.97,3.36],["Naboo","Siemens","MPRAGE",3.14,3.46],["Dagobah","Siemens","",3.01,3.38],["Bespin","Siemens","MPRAGE",3.08,3.39]];
document.getElementById("siteTable").innerHTML=SITEINFO.map(r=>`<tr><td><b>${r[0]}</b></td><td>${r[1]}</td><td>${r[2]||'<span class="muted">not recorded</span>'}</td><td class="num">${r[3].toFixed(2)}</td><td class="num">${r[4].toFixed(2)}</td></tr>`).join("");

/* ---------- generic horizontal bar chart ---------- */
function hbars(svg,rows,opt){
  clear(svg);const W=+svg.viewBox.baseVal.width,H=+svg.viewBox.baseVal.height;
  const L=opt.left||130,R=opt.right||50,T=opt.top||12,B=opt.bottom||28;
  const max=opt.max,min=opt.min||0;const n=rows.length;const bh=(H-T-B)/n;
  const x=v=>L+(v-min)/(max-min)*(W-L-R);
  (opt.ticks||[]).forEach(t=>{el("line",{x1:x(t),x2:x(t),y1:T,y2:H-B,class:"axis"},svg);el("text",{x:x(t),y:H-B+14,"text-anchor":"middle",class:"tick"},svg,opt.fmt?opt.fmt(t):t)});
  if(min<0)el("line",{x1:x(0),x2:x(0),y1:T,y2:H-B,stroke:"var(--muted)"},svg);
  rows.forEach((r,i)=>{const y=T+i*bh;
    el("text",{x:L-8,y:y+bh/2+4,"text-anchor":"end","font-size":"11"},svg,r.label);
    const x0=x(Math.min(0,r.v)),x1=x(Math.max(0,r.v));
    el("rect",{x:x0,y:y+bh*0.18,width:Math.max(1,x1-x0),height:bh*0.64,rx:3,fill:r.color||"var(--muted)"},svg);
    if(r.lo!=null){el("line",{x1:x(r.lo),x2:x(r.hi),y1:y+bh/2,y2:y+bh/2,stroke:"var(--ink)","stroke-width":1.2},svg);[r.lo,r.hi].forEach(v=>el("line",{x1:x(v),x2:x(v),y1:y+bh*0.35,y2:y+bh*0.65,stroke:"var(--ink)","stroke-width":1.2},svg))}
    const tx=r.v>=0?Math.max(x1,r.hi!=null?x(r.hi):x1)+6:x0-6;
    el("text",{x:tx,y:y+bh/2+4,"text-anchor":r.v>=0?"start":"end"},svg,r.text!=null?r.text:r.v);
  });
}

/* ---------- anatomy CV ---------- */
const PIPES=["FreeSurfer 8.1","FreeSurfer 7.4.1","FastSurfer","FastSurfer 1 mm","SynthSeg","SAMSEG","FSL"];
const CV={"Cerebral cortex":[1.2,1.4,3.5,1.2,0.8,2.2,11.9],"Cerebral white matter":[1.2,1.1,2.2,1.0,0.8,3.0,6.6],"Lateral ventricles":[2.1,2.3,2.3,2.5,2.9,1.7,12.8],"Hippocampus":[1.7,3.3,3.5,3.1,1.8,1.5,4.0],"Amygdala":[2.4,3.8,6.9,2.8,1.8,2.6,5.5],"Thalamus":[5.1,6.8,6.6,7.3,1.8,2.2,3.2],"Caudate":[2.0,2.2,2.1,2.0,1.3,2.0,2.0],"Putamen":[1.7,3.1,2.4,2.3,1.3,1.8,2.5],"Pallidum":[2.5,4.7,2.2,2.5,2.1,2.1,2.5],"Brainstem":[1.0,2.5,3.1,2.7,1.2,1.8,4.7],"Cortical thickness":[3.6,3.8,3.7,3.8,null,null,null]};
const cvSel=document.getElementById("cvStruct");
Object.keys(CV).forEach(k=>{const o=document.createElement("option");o.value=k;o.textContent=k;cvSel.appendChild(o)});
cvSel.value="Thalamus";
function drawCV(){const k=cvSel.value;const vals=CV[k];const best=Math.min(...vals.filter(v=>v!=null));
  const rows=PIPES.map((p,i)=>({label:p,v:vals[i]==null?0:vals[i],text:vals[i]==null?"n/a":vals[i].toFixed(1)+"%",color:vals[i]===best?"var(--accent)":"var(--base)"}));
  const mx=Math.max(4,Math.ceil(Math.max(...vals.filter(v=>v!=null))+0.5));const step=mx>8?2:1;const ticks=[];for(let t=0;t<=mx;t+=step)ticks.push(t);
  hbars(document.getElementById("cvSvg"),rows,{max:mx,ticks,fmt:t=>t+"%",left:130,right:60});}
cvSel.addEventListener("change",drawCV);drawCV();

/* ---------- anatomy site offsets ---------- */
const OFF={
  thal:{label:"Thalamus volume",pipes:{"FreeSurfer 8.1":[-7.6,-4.1,5.4,3.0,0.0,3.2],"FreeSurfer 7.4.1":[-9.2,-6.3,4.8,4.9,-0.7,6.4],"FastSurfer":[-11.1,-2.8,5.2,3.8,-1.5,6.4],"FastSurfer 1 mm":[-10.4,-6.8,6.1,4.6,-0.8,7.2],"SynthSeg":[-2.4,-1.8,1.7,1.2,1.1,0.2],"SAMSEG":[-2.2,-2.8,2.0,2.0,-0.1,1.1],"FSL FIRST":[-3.3,0.4,1.6,0.7,1.1,-0.4]},
        note:"Tatooine is 8 to 11% low in every FreeSurfer-style pipeline, and only about 2% low in SynthSeg, SAMSEG and FSL FIRST. That's a contrast effect."},
  thick:{label:"Cortical thickness",pipes:{"FreeSurfer 8.1":[0.3,-7.0,1.7,1.8,0.6,2.6],"FreeSurfer 7.4.1":[-0.3,-7.3,2.0,2.0,0.9,2.6],"FastSurfer":[0.2,-7.4,2.3,2.0,0.8,2.1],"FastSurfer 1 mm":[0.2,-7.4,2.3,2.0,0.9,2.1]},
        note:"Hoth is about 7% thin in all four surface pipelines. No pipeline choice removes it, because the cause is the blurry, interpolated image."},
  ctx:{label:"Cortex volume",pipes:{"FreeSurfer 8.1":[-0.2,-0.7,1.2,0.0,-1.3,1.1],"FastSurfer":[0.8,-6.6,2.8,1.1,-0.1,2.0],"FastSurfer 1 mm":[-0.5,-0.4,1.5,-0.2,-1.3,0.8],"SynthSeg":[-0.6,1.3,0.4,0.3,-0.7,-0.6],"SAMSEG":[3.5,-1.1,0.8,0.3,-2.9,-0.7],"FSL SIENAX":[-1.2,-23.1,6.1,6.4,5.3,6.6]},
        note:"FastSurfer at its default setting runs Hoth's 0.5 mm slices in high-resolution mode and loses 6.6% of cortex; forcing 1 mm fixes it. FSL's tissue classifier labels much of Hoth's blurry grey matter as CSF (−23%)."}
};
let offKey="thal",offPipe="FreeSurfer 8.1";
function offPipeSeg(){const ps=Object.keys(OFF[offKey].pipes);if(!ps.includes(offPipe))offPipe=ps[0];seg("offPipe",ps.map(p=>({key:p,label:p})),offPipe,p=>{offPipe=p;drawOff()})}
function drawOff(){const v=OFF[offKey].pipes[offPipe];
  const rows=SITES.map((s,i)=>({label:s,v:v[i],text:(v[i]>0?"+":"")+v[i].toFixed(1)+"%",color:Math.abs(v[i])>=5?"var(--accent2)":"var(--base)"}));
  const lim=offKey==="ctx"&&offPipe==="FSL SIENAX"?25:12;const ticks=lim===25?[-20,-10,0,10,20]:[-10,-5,0,5,10];
  hbars(document.getElementById("offSvg"),rows,{min:-lim,max:lim,ticks,fmt:t=>(t>0?"+":"")+t+"%",left:80,right:60});
  document.getElementById("offNote").textContent=OFF[offKey].note;}
seg("offMeasure",Object.keys(OFF).map(k=>({key:k,label:OFF[k].label})),offKey,k=>{offKey=k;offPipeSeg();drawOff()});
offPipeSeg();drawOff();

/* ---------- rest ---------- */
const TSNR=[106.4,97.5,94.7,90.4,52.6,92.7];
hbars(document.getElementById("tsnrSvg"),SITES.map((s,i)=>({label:s,v:TSNR[i],text:TSNR[i].toFixed(0),color:s==="Dagobah"?"var(--accent2)":"var(--accent)"})),{max:120,ticks:[0,40,80,120],left:70,right:40});
hbars(document.getElementById("simSvg"),[
  {label:"Same person",v:0.617,lo:0.465,hi:0.733,text:"0.62",color:"var(--accent)"},
  {label:"Others, same site",v:0.476,lo:0.406,hi:0.585,text:"0.48",color:"var(--base)"},
  {label:"Others, other site",v:0.467,lo:0.352,hi:0.610,text:"0.47",color:"var(--base)"}],{max:0.8,ticks:[0,0.2,0.4,0.6,0.8],left:128,right:40,top:20,bottom:30});

const PAIR=[[null,.60,.63,.63,.61,.63],[.60,null,.55,.62,.62,.58],[.63,.55,null,.58,.65,.64],[.63,.62,.58,null,.62,.63],[.61,.62,.65,.62,null,.65],[.63,.58,.64,.63,.65,null]];
(function pairs(){const s=document.getElementById("pairSvg");const L=80,T=60,c=56;const note=document.getElementById("pairNote");
  SITES.forEach((n,i)=>{el("text",{x:L-8,y:T+i*c+c/2+4,"text-anchor":"end"},s,n);el("text",{x:L+i*c+c/2,y:T-10,"text-anchor":"middle",transform:`rotate(-30 ${L+i*c+c/2} ${T-10})`},s,n)});
  const lo=0.55,hi=0.65;
  PAIR.forEach((row,i)=>row.forEach((v,j)=>{
    const g=el("g",{tabindex:v==null?-1:0,role:v==null?"presentation":"button","aria-label":v==null?"":`${SITES[i]} and ${SITES[j]}: ${v}`},s);
    const t=v==null?0:(v-lo)/(hi-lo);
    el("rect",{x:L+j*c+2,y:T+i*c+2,width:c-4,height:c-4,rx:4,fill:v==null?"var(--soft)":"var(--accent)","fill-opacity":v==null?1:(0.15+0.85*Math.max(0,Math.min(1,t)))},g);
    if(v!=null)el("text",{x:L+j*c+c/2,y:T+i*c+c/2+4,"text-anchor":"middle",fill:t>0.55?"var(--surface)":"var(--ink)"},g,v.toFixed(2));
    if(v!=null){const show=()=>{note.textContent=`Same person, ${SITES[i]} vs ${SITES[j]}: r = ${v.toFixed(2)}. Compare with 0.47 for two different people.`};g.addEventListener("mouseenter",show);g.addEventListener("focus",show);g.addEventListener("click",show)}
  }));
})();

const FP=[14,12,15,14,14,14];
hbars(document.getElementById("fpSvg"),SITES.map((s,i)=>({label:s,v:FP[i]/15*100,text:`${FP[i]}/15`,color:"var(--accent)"})),{max:100,ticks:[0,33,67,100],fmt:t=>t+"%",left:70,right:44,top:10,bottom:26});
(function anova(){const s=document.getElementById("anovaSvg");clear(s);
  const rows=[["Person",26.6,11.8],["Site",26.3,29.4],["Noise",47.1,58.8]];const L=60,R=20,T=14,B=30,W=320,H=200;const bh=(H-T-B)/3;const x=v=>L+v/100*(W-L-R);
  [0,20,40,60,80].forEach(t=>{el("line",{x1:x(t),x2:x(t),y1:T,y2:H-B,class:"axis"},s);el("text",{x:x(t),y:H-B+14,"text-anchor":"middle",class:"tick"},s,t+"%")});
  rows.forEach((r,i)=>{const y=T+i*bh;el("text",{x:L-8,y:y+bh/2+4,"text-anchor":"end"},s,r[0]);
    el("rect",{x:x(0),y:y+bh*0.12,width:x(r[1])-x(0),height:bh*0.36,rx:3,fill:"var(--accent)"},s);
    el("rect",{x:x(0),y:y+bh*0.52,width:x(r[2])-x(0),height:bh*0.36,rx:3,fill:"var(--base)"},s);
    el("text",{x:x(r[1])+5,y:y+bh*0.3+4},s,r[1]+"%");el("text",{x:x(r[2])+5,y:y+bh*0.7+4,fill:"var(--muted)"},s,r[2]+"% chance")});
})();

/* ---------- task: Stroop ---------- */
const ST={acc:{label:"Accuracy",unit:"%",d:{Leia:[70,88,98],Luke:[92,94,93],Han:[98,94,98]},min:60,max:100,ticks:[60,70,80,90,100]},
  eff:{label:"Stroop effect",unit:" ms",d:{Leia:[104,263,207],Luke:[96,94,113],Han:[71,-3,21]},min:-50,max:300,ticks:[0,100,200,300]}};
const STS=["Hoth","Endor","Bespin"];const PCOL={Leia:"var(--accent)",Luke:"var(--accent2)",Han:"var(--nf)"};
function drawStroop(k){const s=document.getElementById("stroopSvg");clear(s);const m=ST[k];const L=60,R=110,T=16,B=34,W=640,H=260;
  const xs=i=>L+40+i*((W-L-R-80)/2);const y=v=>T+(m.max-v)/(m.max-m.min)*(H-T-B);
  m.ticks.forEach(t=>{el("line",{x1:L,x2:W-R,y1:y(t),y2:y(t),class:"axis"},s);el("text",{x:L-8,y:y(t)+4,"text-anchor":"end",class:"tick"},s,t+m.unit)});
  STS.forEach((n,i)=>el("text",{x:xs(i),y:H-B+18,"text-anchor":"middle"},s,n));
  PEOPLE.forEach(p=>{const v=m.d[p];el("polyline",{points:v.map((a,i)=>`${xs(i)},${y(a)}`).join(" "),fill:"none",stroke:PCOL[p],"stroke-width":2},s);
    v.forEach((a,i)=>{el("circle",{cx:xs(i),cy:y(a),r:5,fill:PCOL[p]},s)});el("text",{x:xs(2)+12,y:y(v[2])+4,fill:PCOL[p]},s,p)});
  document.getElementById("stroopNote").textContent=k==="eff"?"Interference effect = median correct response time on incongruent trials minus congruent trials. Luke is steady at about 100 ms everywhere; Leia always shows the largest effect and Han the smallest, so the volunteers keep their order across sites.":"Accuracy over 120 trials. Leia's first site (Hoth) was her least accurate session.";}
seg("stroopSeg",Object.keys(ST).map(k=>({key:k,label:ST[k].label})),"eff",drawStroop);drawStroop("eff");

/* ---------- task: group maps ---------- */
const MAPS={
  pics:{label:"Pictures vs baseline",file:"group_full_foodcue_pictures_vs_baseline.png",runs:12,note:"Huge and unambiguous (peak z 27): the whole visual system, from occipital cortex forward along the ventral stream into parietal cortex. Twelve runs, one per volunteer per site."},
  food:{label:"Food vs non-food",file:"group_full_foodcue_food_vs_nonfood.png",runs:12,note:"Red: early visual cortex at the occipital pole responds more to food. Blue: lateral occipital and ventral temporal object areas, and parts of parietal cortex, respond more to non-food objects. Peak z about 9 in both directions."},
  cal:{label:"High- vs low-calorie",file:"group_full_foodcue_highcal_vs_lowcal.png",runs:12,note:"Scattered specks only (peak z 4.8). Even with all twelve runs pooled there is no coherent high- versus low-calorie response, which matches the near-zero reproducibility of single-run maps."},
  stask:{label:"Stroop vs rest",file:"group_full_stroop_task_vs_baseline.png",runs:9,note:"Left motor and somatosensory cortex (the right hand presses the buttons), visual cortex reading the words, and dorsal attention regions. Blue in medial frontal cortex is the default-mode network switching off during the task."},
  sinc:{label:"Incongruent vs congruent",file:"group_full_stroop_incongruent_vs_congruent.png",runs:9,note:"The cognitive-control network: left lateral prefrontal cortex, bilateral parietal cortex and medial frontal cortex. Clear at the group level (peak z 5.3) even though single-run maps barely reproduce within a person."}};
const mapImg=document.getElementById("mapImg"),mapNote=document.getElementById("mapNote");
function showMap(k){const m=MAPS[k];mapImg.src="img/"+m.file;mapImg.alt="Glass-brain map of "+m.label+", "+m.runs+" runs pooled";mapNote.textContent=m.note}
seg("mapSeg",Object.keys(MAPS).map(k=>({key:k,label:MAPS[k].label})),"pics",showMap);showMap("pics");

/* ---------- task: reproducibility ---------- */
const REP={full:{label:"Full runs",rows:[["Pictures vs baseline",.36,.24,.21,.006],["Food vs non-food",.17,.06,.07,.008],["High- vs low-calorie",-.02,.00,-.01,.61],["Stroop task vs rest",.36,.25,.23,.023],["Incongruent vs congruent",.06,.03,.03,.055]],
    note:"Food-cue runs use the fitted break. p is a permutation test of same-person minus different-person similarity."},
  half:{label:"First half only",rows:[["Pictures vs baseline",.25,.19,.16,.003],["Food vs non-food",.08,.04,.05,.08],["High- vs low-calorie",.01,.03,.00,.31]],
    note:"Every food-cue run cut to its first half, which needs no break assumption. Half the data, roughly half the reproducibility."}};
function drawRepro(k){const s=document.getElementById("reproSvg");clear(s);const rows=REP[k].rows;const L=180,R=70,T=20,B=30,W=640,H=300;const n=rows.length;const gh=(H-T-B)/5;const min=-0.05,max=0.45;const x=v=>L+(v-min)/(max-min)*(W-L-R);
  [0,0.1,0.2,0.3,0.4].forEach(t=>{el("line",{x1:x(t),x2:x(t),y1:T,y2:T+gh*n,class:"axis"},s);el("text",{x:x(t),y:T+gh*n+14,"text-anchor":"middle",class:"tick"},s,t.toFixed(1))});
  el("line",{x1:x(0),x2:x(0),y1:T,y2:T+gh*n,stroke:"var(--muted)"},s);
  rows.forEach((r,i)=>{const y=T+i*gh;el("text",{x:L-8,y:y+gh*0.4,"text-anchor":"end"},s,r[0]);el("text",{x:L-8,y:y+gh*0.4+14,"text-anchor":"end",class:"tick"},s,"p = "+r[4]);
    const bar=(v,off,col)=>{const a=x(Math.min(0,v)),b=x(Math.max(0,v));el("rect",{x:a,y:y+off,width:Math.max(1,b-a),height:gh*0.24,rx:2,fill:col},s);return b};
    const e1=bar(r[1],gh*0.08,"var(--accent)");el("text",{x:Math.max(e1,x(0))+5,y:y+gh*0.08+gh*0.2},s,r[1].toFixed(2));
    const diff=(r[2]+r[3])/2;const e2=bar(diff,gh*0.4,"var(--base)");el("text",{x:Math.max(e2,x(0))+5,y:y+gh*0.4+gh*0.2,fill:"var(--muted)"},s,diff.toFixed(2));
  });
  const ly=T+gh*n+36;el("rect",{x:L,y:ly-8,width:10,height:10,fill:"var(--accent)"},s);el("text",{x:L+15,y:ly+1},s,"same person, different site");
  el("rect",{x:L+215,y:ly-8,width:10,height:10,fill:"var(--base)"},s);el("text",{x:L+230,y:ly+1},s,"different people");
  s.setAttribute("viewBox",`0 0 ${W} ${T+gh*n+46}`);
  document.getElementById("reproNote").textContent=REP[k].note;}
seg("reproSeg",Object.keys(REP).map(k=>({key:k,label:REP[k].label})),"full",drawRepro);drawRepro("full");

/* ---------- timing puzzle ---------- */
const H1=[["b",0,24],["nf",24],["lo",40],["hi",56],["nf",72],["hi",88],["lo",104],["hi",120],["b",136,16],["lo",152],["nf",168],["lo",184],["hi",200],["nf",216],["hi",232],["lo",248],["nf",264],["lo",280],["hi",296],["nf",312],["b",328,16]];
const H2=[["b",0,8],["nf",8],["hi",24],["lo",40],["b",56,16],["nf",72],["lo",88],["hi",104],["nf",120],["hi",136],["lo",152],["nf",168],["lo",184],["b",200,16],["hi",216],["lo",232],["hi",248],["nf",264],["hi",280],["lo",296],["nf",312],["b",328,16]];
const RUNS=[
  {id:"hoth-leia",label:"Hoth · Leia",scan:693,fit:5,how:"Short-break peak. The scan stopped at 693 s, exactly where a 5 s break puts the task's end."},
  {id:"hoth-luke",label:"Hoth · Luke",scan:756,fit:0,how:"Clear fit at 0 s. This scan kept running about 66 s past the task's end."},
  {id:"hoth-han",label:"Hoth · Han",scan:693,fit:4,how:"Clear fit at 4 s."},
  {id:"endor-leia",label:"Endor · Leia",scan:900,fit:3,how:"Short-break peak at 3 s, within 2% of the best fit; a 144 s break scored about the same."},
  {id:"endor-luke",label:"Endor · Luke",scan:900,fit:9,how:"Short-break peak at 9 s, within 5% of the best fit (115 s)."},
  {id:"endor-han",label:"Endor · Han",scan:900,fit:6,how:"Clear fit at 6 s."},
  {id:"naboo-leia",label:"Naboo · Leia",scan:900,fit:null,how:"No clear answer, so only the first half (344 s) was analysed."},
  {id:"naboo-luke",label:"Naboo · Luke",scan:900,fit:6,how:"Clear fit at 6 s."},
  {id:"naboo-han",label:"Naboo · Han",scan:900,fit:3,how:"Clear fit at 3 s, the sharpest of all runs."},
  {id:"bespin-leia",label:"Bespin · Leia",scan:528,fit:null,how:"Only 528 s of this scan survived, too little of the second half to fit; first half only."},
  {id:"bespin-luke",label:"Bespin · Luke",scan:900,fit:9,how:"Clear fit at 9 s."},
  {id:"bespin-han",label:"Bespin · Han",scan:900,fit:4,how:"Clear fit at 4 s."}];
const runSel=document.getElementById("runSel");RUNS.forEach(r=>{const o=document.createElement("option");o.value=r.id;o.textContent=r.label;runSel.appendChild(o)});
const brk=document.getElementById("brk"),brkVal=document.getElementById("brkVal"),tnote=document.getElementById("timeNote");
const COL={hi:"var(--hi)",lo:"var(--lo)",nf:"var(--nf)",b:"var(--base)"};
function drawTime(){const r=RUNS.find(x=>x.id===runSel.value);const b=+brk.value;brkVal.textContent=b+" s";
  const s=document.getElementById("timeSvg");clear(s);const L=20,R=20,W=680,maxT=1000;const x=t=>L+t/maxT*(W-L-R);
  el("rect",{x:x(0),y:30,width:x(r.scan)-x(0),height:70,fill:"var(--accent-soft)",stroke:"var(--accent)","stroke-dasharray":"4 3"},s);
  el("text",{x:x(r.scan)-4,y:24,"text-anchor":"end",fill:"var(--accent)"},s,`scan ends ${r.scan} s`);
  const blk=(t,d,k,y,h)=>el("rect",{x:x(t),y,width:Math.max(0.5,x(t+d)-x(t)),height:h,fill:COL[k],opacity:t>=r.scan?0.35:1},s);
  H1.forEach(e=>blk(e[1],e[2]||16,e[0],45,40));
  if(b>0)el("rect",{x:x(344),y:45,width:x(344+b)-x(344),height:40,fill:"var(--accent2)",opacity:.8},s);
  H2.forEach(e=>blk(344+b+e[1],e[2]||16,e[0],45,40));
  [0,200,400,600,800,1000].forEach(t=>{el("line",{x1:x(t),x2:x(t),y1:104,y2:110,stroke:"var(--muted)"},s);el("text",{x:x(t),y:124,"text-anchor":"middle",class:"tick"},s,t+" s")});
  const end=688+b;const out=end-r.scan;
  el("text",{x:x(0),y:146,"text-anchor":"start",class:"tick"},s,"first half: fixed, starts at the trigger");
  el("text",{x:x(Math.min(344+b,640)),y:162,"text-anchor":"start",class:"tick"},s,"second half: moves with the break");
  let msg=`Task ends at ${end} s. `+(out>0?`That's ${out} s after the scan stopped, so the faded blocks were never imaged.`:`That's ${-out} s before the scan stopped.`);
  if(fitShown)msg+=` Fitted: ${r.fit==null?"not identified":r.fit+" s"}. ${r.how}`;
  tnote.textContent=msg;}
let fitShown=false;
document.getElementById("fitBtn").addEventListener("click",()=>{const r=RUNS.find(x=>x.id===runSel.value);fitShown=true;if(r.fit!=null)brk.value=r.fit;drawTime()});
runSel.addEventListener("change",()=>{fitShown=false;brk.value=0;drawTime()});brk.addEventListener("input",drawTime);
runSel.value="hoth-leia";drawTime();

/* ---------- ladder ---------- */
const LAD=[["Brain volumes (SynthSeg)","CV 0.8 to 2.9%",95],["Resting-state connectome","0.62 vs 0.47",70],["Pictures vs baseline map","0.36 vs 0.22",48],["Stroop task vs rest map","0.36 vs 0.24",46],["Food vs non-food map","0.17 vs 0.07",26],["Incongruent vs congruent","0.06 vs 0.03",9],["High- vs low-calorie","no signature",2]];
document.getElementById("ladder").innerHTML="<h3>Within-person reproducibility, highest to lowest</h3>"+LAD.map(r=>`<div class="rung"><span>${r[0]}</span><div class="track"><div class="bar" style="width:${r[2]}%"></div></div><span class="v">${r[1]}</span></div>`).join("")+`<p class="caption">Bar lengths show the rank order only; the units differ between rows (CV for volumes, correlation for maps).</p>`;

/* ---------- quiz ---------- */
const Q=[
 {q:"Leia's thalamus is 8% smaller at Tatooine in FreeSurfer but only 2% smaller in SynthSeg. What's the most likely cause?",o:["Leia's thalamus shrank between visits","Tatooine's T1 contrast moves the boundary that FreeSurfer-style pipelines detect","SynthSeg is less accurate","Head motion at Tatooine"],a:1,w:"All three volunteers show it, only at Tatooine, and only in intensity-boundary pipelines. Tatooine used a different T1 sequence with the highest contrast."},
 {q:"Every surface pipeline finds cortex 7% thinner at Hoth. Which fix would work?",o:["Switch from FreeSurfer to FastSurfer","Use a newer FreeSurfer version","Acquire a true isotropic 1 mm T1 without slice interpolation, or model site statistically","Average more subjects"],a:2,w:"The offset survives every pipeline, so it's in the image itself. Fix the acquisition, or include a site term (for example ComBat) when analysing existing data."},
 {q:"Two different people scanned at the same site have connectome similarity 0.48; two different people at different sites, 0.47. What does that tell you?",o:["Sites leave a strong fingerprint","Resting-state connectomes carry no detectable site signature","The data are too noisy to use","Same-site scans should be excluded"],a:1,w:"If the scanner left a mark, people sharing a scanner would look more alike. They don't, while the same person at two sites scores 0.62."},
 {q:"The high- versus low-calorie contrast shows no within-person reproducibility from one run. What's the best response?",o:["Conclude the brain doesn't distinguish calorie content","Collect more runs per person or use region-of-interest measures","Use a stricter threshold","Remove the noisiest site"],a:1,w:"It's a small difference between two similar conditions. One run gives a noisy map; more data or a targeted ROI measure is needed before using it for individuals."},
 {q:"The food-cue log had picture order but no times. What should the study have logged to avoid reconstructing the timing?",o:["The participant's name","Each stimulus onset time and the scanner trigger","The room temperature","Only the total run length"],a:1,w:"With onsets and the trigger time in the log, events can be built directly. Without them we had to estimate a self-paced break from the brain data."}];
const qz=document.getElementById("quiz");
Q.forEach((it,qi)=>{const d=document.createElement("div");d.className="q";d.innerHTML=`<b>${qi+1}. ${it.q}</b><div class="opts"></div><p class="why" hidden></p>`;
  const opts=d.querySelector(".opts"),why=d.querySelector(".why");
  it.o.forEach((t,i)=>{const b=document.createElement("button");b.type="button";b.textContent=t;b.addEventListener("click",()=>{opts.querySelectorAll("button").forEach((x,j)=>{x.classList.remove("right","wrong");if(j===it.a)x.classList.add("right")});if(i!==it.a)b.classList.add("wrong");why.textContent=(i===it.a?"Correct. ":"Not quite. ")+it.w;why.hidden=false});opts.appendChild(b)});
  qz.appendChild(d)});

})();
