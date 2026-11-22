import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

// 1) Crie um projeto em https://supabase.com
// 2) Cole a URL e a chave anon/public do projeto abaixo.
const SUPABASE_URL = "COLE_A_URL_DO_SEU_PROJETO";
const SUPABASE_ANON_KEY = "COLE_A_CHAVE_ANON_PUBLIC";
const configured = !SUPABASE_URL.startsWith("COLE_") && !SUPABASE_ANON_KEY.startsWith("COLE_");
const supabase = configured ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

const $ = (id) => document.getElementById(id);
let currentUser = null, activeChat = null, refreshTimer = null;

function toast(message) {
  const el = $("toast"); if (!el) return;
  el.textContent = message; el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 2800);
}
function authMessage(message) { $("auth-message").textContent = message; }
function initials(name) { return (name || "?").trim().slice(0,1).toUpperCase(); }
function safe(value) { return String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
function dateLabel(value) { return new Date(value).toLocaleString("pt-BR",{dateStyle:"short",timeStyle:"short"}); }

async function requireConfig() {
  if (!configured) { authMessage("Configure SUPABASE_URL e SUPABASE_ANON_KEY no arquivo src/app.js antes de usar o site."); return false; }
  return true;
}
$("auth-form").addEventListener("submit", async e => {
  e.preventDefault(); if (!await requireConfig()) return;
  const email=$("email").value.trim(), password=$("password").value;
  const {error}=await supabase.auth.signInWithPassword({email,password});
  authMessage(error ? error.message : "Login realizado.");
});
$("signup-btn").addEventListener("click", async () => {
  if (!await requireConfig()) return;
  const email=$("email").value.trim(), password=$("password").value;
  if(password.length<8){authMessage("Use uma senha com pelo menos 8 caracteres.");return;}
  const {data,error}=await supabase.auth.signUp({email,password,options:{emailRedirectTo:location.origin+location.pathname}});
  if(error) authMessage(error.message);
  else authMessage(data.session ? "Conta criada. Você já pode entrar." : "Conta criada! Enviamos um código/link de confirmação para seu e-mail. Confira a caixa de entrada e o spam.");
});
$("code-form").addEventListener("submit", async e => {
  e.preventDefault(); if (!await requireConfig()) return;
  const email=$("email").value.trim(), token=$("otp").value.trim();
  if(!email || !token){authMessage("Informe o e-mail usado no cadastro e o código recebido.");return;}
  const {error}=await supabase.auth.verifyOtp({email,token,type:"signup"});
  authMessage(error ? error.message : "E-mail confirmado. Você já pode usar a AURA.");
});

async function loadProfile() {
  const {data}=await supabase.from("profiles").select("*").eq("id",currentUser.id).maybeSingle();
  const name=data?.display_name || currentUser.email.split("@")[0];
  $("my-name").textContent=name; $("top-user").textContent=name;
  $("my-email").textContent=currentUser.email; $("my-avatar").textContent=initials(name);
  $("profile-name").value=data?.display_name || "";
  $("profile-bio").value=data?.bio || "";
}
function showApp(session) {
  currentUser=session.user; $("auth-view").classList.add("hidden"); $("app-view").classList.remove("hidden");
  loadProfile(); loadFeed(); loadPeople();
  if(refreshTimer) clearInterval(refreshTimer);
  refreshTimer=setInterval(()=>{if(activeChat)loadMessages();},5000);
}
async function loadFeed() {
  const box=$("feed-list"); box.innerHTML='<div class="card muted">Carregando...</div>';
  const {data,error}=await supabase.from("posts").select("id,content,created_at,user_id,profiles(display_name)").order("created_at",{ascending:false}).limit(60);
  if(error){box.innerHTML=`<div class="card">Não foi possível carregar o feed: ${safe(error.message)}</div>`;return;}
  if(!data?.length){box.innerHTML='<div class="card muted">Ainda não há publicações. Seja a primeira pessoa a postar!</div>';return;}
  box.innerHTML=data.map(p=>{const name=p.profiles?.display_name||"Pessoa da comunidade";return `<article class="card"><div class="post-head"><div class="avatar">${safe(initials(name))}</div><div class="post-meta"><strong>${safe(name)}</strong><small>${safe(dateLabel(p.created_at))}</small></div></div><div class="post-content">${safe(p.content)}</div><div class="post-actions">${p.user_id!==currentUser.id?`<button data-message-user="${safe(p.user_id)}">Enviar mensagem privada</button>`:"<span class='muted tiny'>Sua publicação</span>"}</div></article>`}).join("");
  box.querySelectorAll("[data-message-user]").forEach(b=>b.addEventListener("click",()=>{switchTab("messages");openChat(b.dataset.messageUser);}));
}
$("publish-btn").addEventListener("click",async()=>{
  const content=$("post-content").value.trim(); if(!content)return toast("Escreva algo antes de publicar.");
  const {error}=await supabase.from("posts").insert({user_id:currentUser.id,content});
  if(error)toast(error.message);else{$("post-content").value="";toast("Publicação compartilhada!");loadFeed();}
});
$("refresh-feed").addEventListener("click",loadFeed);

function switchTab(tab){
  document.querySelectorAll(".tab").forEach(x=>x.classList.add("hidden"));
  $(`${tab}-tab`).classList.remove("hidden");
  document.querySelectorAll(".side-link").forEach(x=>x.classList.toggle("active",x.dataset.tab===tab));
  if(tab==="messages")loadPeople();
}
document.querySelectorAll(".side-link").forEach(b=>b.addEventListener("click",()=>switchTab(b.dataset.tab)));

let peopleCache=[];
async function loadPeople(){
  const {data,error}=await supabase.from("profiles").select("id,display_name").neq("id",currentUser.id).order("display_name");
  if(error){$("people-list").textContent=error.message;return;}
  peopleCache=data||[]; renderPeople();
}
function renderPeople(){
  const q=$("people-search").value.toLowerCase();
  const people=peopleCache.filter(p=>(p.display_name||"").toLowerCase().includes(q));
  $("people-list").innerHTML=people.map(p=>`<div class="person ${activeChat===p.id?"selected":""}" data-person="${safe(p.id)}"><div class="avatar">${safe(initials(p.display_name))}</div><span>${safe(p.display_name||"Pessoa")}</span></div>`).join("")||'<small class="muted">Nenhuma pessoa encontrada.</small>';
  $("people-list").querySelectorAll("[data-person]").forEach(el=>el.addEventListener("click",()=>openChat(el.dataset.person)));
}
$("people-search").addEventListener("input",renderPeople);
async function openChat(userId){
  activeChat=userId;renderPeople();
  const person=peopleCache.find(p=>p.id===userId);
  $("chat-heading").textContent=person?.display_name||"Conversa privada";
  $("message-input").disabled=false;$("send-btn").disabled=false;
  await loadMessages();
}
async function loadMessages(){
  if(!activeChat)return;
  const {data,error}=await supabase.from("messages").select("id,sender_id,receiver_id,content,created_at").or(`and(sender_id.eq.${currentUser.id},receiver_id.eq.${activeChat}),and(sender_id.eq.${activeChat},receiver_id.eq.${currentUser.id})`).order("created_at",{ascending:true}).limit(200);
  if(error){$("chat-list").textContent=error.message;return;}
  const box=$("chat-list"), nearBottom=box.scrollHeight-box.scrollTop-box.clientHeight<80;
  box.innerHTML=(data||[]).map(m=>`<div class="bubble ${m.sender_id===currentUser.id?"mine":""}">${safe(m.content)}<small>${safe(dateLabel(m.created_at))}</small></div>`).join("")||'<small class="muted">Esta conversa ainda está vazia. Diga olá!</small>';
  if(nearBottom)box.scrollTop=box.scrollHeight;
}
$("message-form").addEventListener("submit",async e=>{
  e.preventDefault();const content=$("message-input").value.trim();if(!content||!activeChat)return;
  $("send-btn").disabled=true;
  const {error}=await supabase.from("messages").insert({sender_id:currentUser.id,receiver_id:activeChat,content});
  $("send-btn").disabled=false;
  if(error)toast(error.message);else{$("message-input").value="";loadMessages();}
});
$("save-profile").addEventListener("click",async()=>{
  const display_name=$("profile-name").value.trim(),bio=$("profile-bio").value.trim();
  if(!display_name)return $("profile-status").textContent="Informe um nome de exibição.";
  const {error}=await supabase.from("profiles").upsert({id:currentUser.id,display_name,bio,updated_at:new Date().toISOString()});
  $("profile-status").textContent=error?error.message:"Perfil atualizado!";
  if(!error)loadProfile();
});
$("logout-btn").addEventListener("click",async()=>{await supabase.auth.signOut();currentUser=null;$("app-view").classList.add("hidden");$("auth-view").classList.remove("hidden");});

if(configured){
  supabase.auth.onAuthStateChange((_event,session)=>{if(session?.user&&!currentUser)showApp(session);else if(!session?.user){$("app-view").classList.add("hidden");$("auth-view").classList.remove("hidden");}});
  const {data:{session}}=await supabase.auth.getSession();if(session)showApp(session);
}else authMessage("Primeiro configure seu projeto Supabase. Veja o arquivo README.md.");
