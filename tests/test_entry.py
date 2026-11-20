import json,os,pty,select,shutil,subprocess,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
FAKE='hf_'+'synthetic'*3


class EntryTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.base=Path(self.temp.name)
  self.repo=self.base/'repo';shutil.copytree(ROOT,self.repo,ignore=shutil.ignore_patterns('.git','.run','__pycache__'))
  self.env={k:v for k,v in os.environ.items() if k not in ['HF_TOKEN','BLUR_HF_TOKEN_FILE','BLUR_RUN_ROOT']}
  self.env['XDG_CONFIG_HOME']=str(self.base/'config')
  for name in ['first','all']:
   (self.repo/'launchers'/f'{name}.sh').write_text('#!/bin/bash\nset -eu\n[[ -r "$BLUR_HF_TOKEN_FILE" ]]\n[[ "$(stat -c %a "$BLUR_HF_TOKEN_FILE")" == 600 ]]\nprintf "'+name+' ready\\n"\nprintf "%s" "$BLUR_HF_TOKEN_FILE" > "$BLUR_RUN_ROOT/test-token-path"\n')
 def tearDown(self):self.temp.cleanup()
 def run_entry(self,*args,env=None):
  return subprocess.run(['bash',str(self.repo/'run.sh'),*args],env=env or self.env,stdin=subprocess.DEVNULL,capture_output=True,text=True)
 def test_help_does_not_require_token(self):self.assertEqual(self.run_entry('--help').returncode,0)
 def test_noninteractive_missing_token_fails_clearly(self):
  p=self.run_entry();self.assertEqual(p.returncode,2);self.assertIn('No interactive terminal',p.stderr)
 def test_env_credential_is_ephemeral_and_not_logged(self):
  p=self.run_entry(env={**self.env,'HF_TOKEN':FAKE});self.assertEqual(p.returncode,0,p.stderr)
  token=Path((self.repo/'.run/test-token-path').read_text());self.assertFalse(token.exists())
  self.assertNotIn(FAKE,p.stdout+p.stderr)
  self.assertFalse((self.base/'config/humanplus-blur/token.private').exists())
 def test_explicit_file_and_alternate_work_path(self):
  token=self.base/'credential';token.write_text(FAKE+'\n');token.chmod(0o600)
  work=self.base/'scratch'
  p=self.run_entry('--token-file',str(token),'--work-dir',str(work),'--all')
  self.assertEqual(p.returncode,0,p.stderr);self.assertIn('all ready',p.stdout)
  self.assertEqual(Path((work/'test-token-path').read_text()),token)
 def test_world_readable_token_is_rejected(self):
  token=self.base/'credential';token.write_text(FAKE+'\n');token.chmod(0o644)
  p=self.run_entry('--token-file',str(token));self.assertEqual(p.returncode,2)
  self.assertNotIn(FAKE,p.stdout+p.stderr)
 def test_invalid_env_token_is_not_disclosed(self):
  bad='not-a-valid-token'
  p=self.run_entry(env={**self.env,'HF_TOKEN':bad});self.assertEqual(p.returncode,2)
  self.assertNotIn(bad,p.stdout+p.stderr)
 def test_interactive_hidden_entry_then_cached_reuse(self):
  pid,fd=pty.fork()
  if pid==0:os.execve('/bin/bash',['bash',str(self.repo/'run.sh')],self.env)
  data=b'';sent=False;deadline=time.monotonic()+8
  try:
   while time.monotonic()<deadline:
    ready,_,_=select.select([fd],[],[],.2)
    if ready:
     try:chunk=os.read(fd,65536)
     except OSError:break
     if not chunk:break
     data+=chunk
     if b'Paste HF Token' in data and not sent:os.write(fd,(FAKE+'\n').encode());sent=True
   _,status=os.waitpid(pid,0)
  finally:os.close(fd)
  self.assertTrue(sent);self.assertEqual(os.waitstatus_to_exitcode(status),0,data.decode())
  self.assertNotIn(FAKE.encode(),data)
  cache=self.base/'config/humanplus-blur/token.private'
  self.assertEqual(cache.read_text().strip(),FAKE);self.assertEqual(cache.stat().st_mode&0o777,0o600)
  self.assertFalse(str(cache).startswith(str(self.repo)))
  p=self.run_entry('--all');self.assertEqual(p.returncode,0,p.stderr);self.assertIn('all ready',p.stdout)

if __name__=='__main__':unittest.main()
