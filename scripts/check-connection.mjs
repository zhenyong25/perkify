import { loadEnv } from 'vite'
const e=loadEnv('development',process.cwd(),'VITE_')
console.log('Project URL configured:', Boolean(e.VITE_SUPABASE_URL))
console.log('Publishable key configured:', Boolean(e.VITE_SUPABASE_PUBLISHABLE_KEY))
if(e.VITE_SUPABASE_URL && e.VITE_SUPABASE_PUBLISHABLE_KEY){
 for(const [path,method] of [['/auth/v1/settings','GET'],['/rest/v1/rpc/perkify_get_wallet','POST']]){
  const r=await fetch(e.VITE_SUPABASE_URL+path,{method,headers:{apikey:e.VITE_SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},...(method==='POST'?{body:'{}'}:{})})
  const body=await r.json()
  console.log(path, 'HTTP',r.status,method==='GET'?{emailAuth:body.external?.email,signupDisabled:body.disable_signup}:{code:body.code,message:body.message})
 }
}
