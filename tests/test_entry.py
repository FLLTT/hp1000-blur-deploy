import hashlib, importlib.util, json, os, shutil, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class EntryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.base=Path(self.tmp.name)
  self.repo=self.base/'repo';shutil.copytree(ROOT,self.repo,ignore=shutil.ignore_patterns('.git','.run','__pycache__'))
  self.env={k:v for k,v in os.environ.items() if k not in ['HF_TOKEN','BLUR_HF_TOKEN_FILE','BLUR_RUN_ROOT']}
  for name in ['first','all']:
   (self.repo/'launchers'/f'{name}.sh').write_text('#!/bin/bash\nset -eu\nprintf "'+name+' ready\\n"\n[[ -z "${BLUR_HF_TOKEN_FILE:-}" ]] || printf "%s" "$BLUR_HF_TOKEN_FILE" > "$BLUR_RUN_ROOT/token-path"\n')
 def tearDown(self):self.tmp.cleanup()
 def run_entry(self,*args,env=None):return subprocess.run(['bash',str(self.repo/'run.sh'),*args],env=env or self.env,stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=10)
 def test_public_no_terminal_no_token(self):
  p=self.run_entry();self.assertEqual(p.returncode,0,p.stderr);self.assertIn('first ready',p.stdout)
 def test_help_no_token(self):self.assertEqual(self.run_entry('--help').returncode,0)
 def test_all_and_custom_work(self):
  p=self.run_entry('--all','--work-dir',str(self.base/'scratch'));self.assertEqual(p.returncode,0,p.stderr);self.assertIn('all ready',p.stdout)
 def test_explicit_upload_token(self):
  p=self.base/'secret';p.write_text('hf_synthetic_test_only');p.chmod(0o600)
  result=self.run_entry('--token-file',str(p));self.assertEqual(result.returncode,0,result.stderr);self.assertNotIn(p.read_text(),result.stdout+result.stderr)
 def test_readable_token_rejected(self):
  p=self.base/'secret';p.write_text('hf_synthetic_test_only');p.chmod(0o644);self.assertEqual(self.run_entry('--token-file',str(p)).returncode,2)
 def test_environment_token_cleanup(self):
  result=self.run_entry(env={**self.env,'HF_TOKEN':'hf_synthetic_test_only'});self.assertEqual(result.returncode,0,result.stderr)
  p=Path((self.repo/'.run/token-path').read_text());self.assertFalse(p.exists());self.assertNotIn('hf_synthetic_test_only',result.stdout+result.stderr)
 def test_no_interactive_token_option(self):self.assertEqual(self.run_entry('--new-token').returncode,2)

if __name__=='__main__':unittest.main()
