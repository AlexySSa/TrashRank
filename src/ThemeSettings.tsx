import React,{useLayoutEffect,useState} from 'react';
import {Palette,Check} from 'lucide-react';
import {themes,normalizeTheme,themeStorageKey} from './themes.mjs';
import type {Theme} from './themes.mjs';
import './themes.css';
function read(id:string|undefined):Theme{try{return normalizeTheme(id?localStorage.getItem(themeStorageKey(id)):null)}catch{return 'green'}}
export function useThemePreference(id:string|undefined):[Theme,(value:Theme)=>void]{
 const [selection,setSelection]=useState<{id:string|undefined;theme:Theme}>(()=>({id,theme:read(id)}));
 const theme=selection.id===id?selection.theme:read(id);
 useLayoutEffect(()=>{document.documentElement.dataset.theme=theme;const meta=document.querySelector('meta[name="theme-color"]');meta?.setAttribute('content',themes.find(t=>t.id===theme)?.bg??'#101512');},[theme]);
 function choose(value:Theme){const next=normalizeTheme(value);if(!id)return;try{localStorage.setItem(themeStorageKey(id),next)}catch{}setSelection({id,theme:next})}
 return [theme,choose];
}
export function ThemeSettings({theme,onChange}:{theme:Theme;onChange:(theme:Theme)=>void}){
 return <section className="card theme-settings"><div className="section-head"><h2><Palette size={21}/> Apariencia</h2><span className="pill">Personal</span></div><p>Elige el tema que más te guste. Solo cambia tu interfaz.</p><div className="theme-grid" role="group" aria-label="Temas de TrashRank">{themes.map(t=><button key={t.id} type="button" aria-pressed={theme===t.id} aria-label={'Tema '+t.name} className={'theme-option '+(theme===t.id?'chosen':'')} onClick={()=>onChange(t.id)}><span className="theme-preview" style={{background:t.bg,color:t.text,borderColor:t.border}}><span className="theme-preview-head"><i style={{background:t.accent}}/><b>TrashRank</b><span style={{background:t.accent}}/></span><span className="theme-preview-card" style={{background:t.card,borderColor:t.border}}><i style={{background:t.text,opacity:.7}}/><i style={{background:t.text,opacity:.25}}/><span style={{background:t.accent}}/></span></span><span className="theme-label">{t.name}{theme===t.id&&<Check size={16}/>}</span></button>)}</div><small>Tu elección se guarda para tu cuenta en este navegador.</small></section>
}