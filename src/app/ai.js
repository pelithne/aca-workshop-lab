import express from 'express';
import fetch from 'node-fetch';
const router = express.Router();
router.post('/openai', async (req,res)=>{
  try {
    const endpoint=process.env.AZURE_OPENAI_ENDPOINT;
    const deployment=process.env.AZURE_OPENAI_DEPLOYMENT;
    if(!endpoint||!deployment) return res.status(400).json({error:'AOAI not configured'});
    const url=`${endpoint}openai/deployments/${deployment}/chat/completions?api-version=2024-02-15-preview`;
    const body=req.body?.messages?req.body:{messages:[{role:'user',content:'Say hello'}]};
    const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    const data=await r.json();
    res.status(r.status).json(data);
  } catch(e){res.status(500).json({error:e.message});}
});
router.post('/ollama', async (req,res)=>{
  try {
    const base=process.env.OLLAMA_BASE||'http://127.0.0.1:11434';
    const model=process.env.OLLAMA_MODEL||'phi3.5:latest';
    const prompt=req.body?.prompt||'Say hello from Ollama';
    const r=await fetch(`${base}/api/generate`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({model,prompt,stream:false})});
    const data=await r.json();
    res.status(r.status).json(data);
  } catch(e){res.status(500).json({error:e.message});}
});
export default router;
