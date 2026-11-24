"""Create a verified public-read overlay without changing the frozen R5 payload."""
import hashlib
import json
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Unexpected frozen source; refusing to patch')
    return text.replace(old, new, 1)


def configure(root):
    root = Path(root)
    marker = root / 'PUBLIC_MODE.json'
    if marker.exists():
        return
    for row in (root / 'SHA256SUMS').read_text().splitlines():
        expected, name = row.split('  ', 1)
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise ValueError('Frozen payload integrity mismatch')
    transport = (root / 'hf_transport.py').read_text()
    transport = replace_once(transport, 'self.token = read_token()',
        "self.token = read_token() if os.environ.get('BLUR_HF_TOKEN_FILE') else False")
    transport = replace_once(transport,
        "if info.private is not True:\n            raise ValueError('HF repository is public; refusing all video transfers')",
        "if info.private is not False:\n            raise ValueError('Public mode requires a public repository')")
    transport = replace_once(transport,
        "if info.private is not True:\n            raise ValueError('HF repository became public; refusing upload')",
        "if info.private is not False:\n            raise ValueError('Public mode repository visibility changed')")
    transport = replace_once(transport, "path = Path(path)\n        key = self.hf['output_prefix']",
        "path = Path(path)\n        if not self.token:\n            return {'object': name, 'bytes': path.stat().st_size, 'sha256': sha(path),\n                    'local_only': True, 'remote_readback_sha256_verified': False}\n        key = self.hf['output_prefix']")
    worker = (root / 'worker.py').read_text()
    worker = replace_once(worker, 'save(work / "reports/return_receipt.json", confirmation)',
        'save(work / "reports/return_receipt.json", confirmation)\n'
        '            if confirmation.get("local_only"):\n'
        '                receipt.update(status="completed_local_only", result_upload_performed=False,\n'
        '                               result_location=str(work / "output"))\n'
        '                save(work / "reports/execution.json", receipt)\n'
        '                save(completion, receipt)\n'
        '                print("PUBLIC DOWNLOAD MODE: outputs verified locally; no result uploaded. "\n'
        '                      "Use --token-file for automatic HF upload.", flush=True)')
    # Atomic replacement breaks the hardlink, preserving the original frozen base.
    for name, text in [('hf_transport.py', transport), ('worker.py', worker)]:
        compile(text, name, 'exec')
        tmp = root / (name + '.public-new')
        tmp.write_text(text)
        tmp.replace(root / name)
    lines = []
    for row in (root / 'SHA256SUMS').read_text().splitlines():
        _, name = row.split('  ', 1)
        lines.append(hashlib.sha256((root / name).read_bytes()).hexdigest() + '  ' + name)
    tmp = root / 'SHA256SUMS.public-new'
    tmp.write_text('\n'.join(lines) + '\n')
    tmp.replace(root / 'SHA256SUMS')
    marker.write_text(json.dumps({'mode': 'public_read_optional_authenticated_write',
                                  'local_only_without_token': True}) + '\n')


if __name__ == '__main__':
    configure(sys.argv[1])
