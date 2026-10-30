// Keep Windows candidates at the actual caret after host-controlled CEF zoom.
// Normalized coordinates make this independent of Godot stretch and OS DPI.
export function installCaretTracking(send){
  let queued=0;
  const update=()=>{
    cancelAnimationFrame(queued);
    queued=requestAnimationFrame(()=>{
      const target=document.activeElement;
      let rect;
      if(target?.isContentEditable){
        const selection=getSelection();
        if(selection?.rangeCount){
          const range=selection.getRangeAt(0).cloneRange();range.collapse(false);
          rect=range.getClientRects()[0];
          if(!rect||!rect.height){
            const node=range.endContainer.nodeType===3?range.endContainer.parentElement:range.endContainer;
            const line=node?.getBoundingClientRect();
            if(line)rect={left:line.left,bottom:line.top+(parseFloat(getComputedStyle(node).lineHeight)||22)};
          }
        }
      }else if(target?.matches('input:not([type=checkbox]),textarea')){
        const style=getComputedStyle(target),box=target.getBoundingClientRect(),mirror=document.createElement('div');
        for(const prop of ['font','lineHeight','letterSpacing','padding','border','boxSizing','wordBreak','overflowWrap','textIndent'])mirror.style[prop]=style[prop];
        Object.assign(mirror.style,{position:'fixed',visibility:'hidden',left:box.left+'px',top:box.top+'px',width:box.width+'px',whiteSpace:target.tagName==='INPUT'?'pre':'pre-wrap'});
        mirror.textContent=target.value.slice(0,target.selectionEnd||0);
        const marker=document.createElement('span');marker.textContent='\u200b';mirror.append(marker);document.body.append(mirror);
        const measured=marker.getBoundingClientRect();
        rect={left:measured.left-target.scrollLeft,bottom:measured.bottom-target.scrollTop};mirror.remove();
      }
      send(rect?{x:Math.max(0,Math.min(1,rect.left/innerWidth)),y:Math.max(0,Math.min(1,rect.bottom/innerHeight))}:{x:-1,y:-1});
    });
  };
  for(const name of ['selectionchange','input','compositionupdate','focusin','focusout','keyup','scroll'])document.addEventListener(name,update,true);
  window.addEventListener('resize',update);
}
