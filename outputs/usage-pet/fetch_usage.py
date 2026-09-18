"""Read quota through the official local Codex app-server; never read auth files."""
import datetime, json, os, pathlib, queue, shutil, subprocess, sys, threading, time

def normalize_tokens(result):
    def valid(value):
        return isinstance(value, int) and not isinstance(value, bool) and value >= 0
    today = datetime.date.today().isoformat()
    for bucket in result.get('dailyUsageBuckets') or []:
        if bucket.get('startDate') == today and valid(bucket.get('tokens')):
            return {'label': '今日 Token', 'value': bucket['tokens']}
    total = (result.get('summary') or {}).get('lifetimeTokens')
    return {'label': '累计 Token', 'value': total} if valid(total) else {'label': 'Token 用量', 'value': None}

def normalize(result):
    buckets = result.get('rateLimitsByLimitId')
    bucket = buckets.get('codex', {}) if isinstance(buckets, dict) else result.get('rateLimits', {})
    output = {}
    for key, duration in [('five', 300), ('week', 10080)]:
        window = next((w for w in [bucket.get('primary'), bucket.get('secondary')] if isinstance(w, dict) and w.get('windowDurationMins') == duration), {})
        used = window.get('usedPercent')
        output[key] = {'remaining': max(0, min(100, 100-used)) if isinstance(used, (float, int)) and not isinstance(used, bool) else None, 'reset': window.get('resetsAt')}
    return output

def fetch():
    executable = shutil.which('codex.exe')
    if not executable:
        root = pathlib.Path(os.environ.get('LOCALAPPDATA', '')) / 'OpenAI/Codex/bin'
        candidates = sorted(root.glob('*/codex.exe'), key=lambda p: p.stat().st_mtime, reverse=True)
        if not candidates:
            raise RuntimeError('codex_missing')
        executable = str(candidates[0])
    proc = subprocess.Popen([executable, 'app-server', '--stdio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW)
    messages = queue.Queue()
    def reader():
        for line in proc.stdout:
            try: messages.put(json.loads(line))
            except ValueError: pass
        messages.put({'closed': True})
    threading.Thread(target=reader, daemon=True).start()
    deadline = time.monotonic()+20
    def send(obj):
        proc.stdin.write(json.dumps(obj)+'\n'); proc.stdin.flush()
    def receive(identifier):
        while True:
            message = messages.get(timeout=max(.01, deadline-time.monotonic()))
            if message.get('closed'): raise RuntimeError('server_closed')
            if message.get('id') == identifier:
                if 'error' in message: raise RuntimeError('unavailable')
                return message['result']
    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'usage_pet', 'version': '1.0.0'}}})
        receive(1)
        send({'method': 'initialized', 'params': {}})
        send({'id': 2, 'method': 'account/rateLimits/read'})
        output = normalize(receive(2))
        try:
            send({'id': 3, 'method': 'account/usage/read'})
            output['tokens'] = normalize_tokens(receive(3))
        except Exception:
            output['tokens'] = {'label': 'Token 用量', 'value': None}
        return output
    finally:
        proc.terminate()
        try: proc.wait(timeout=3)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()

if __name__ == '__main__':
    target = pathlib.Path(sys.argv[1])
    try: data = {'ok': True, 'at': time.time(), **fetch()}
    except Exception: data = {'ok': False, 'at': time.time(), 'error': '暂时无法读取，请确认 Codex 已登录'}
    temp = target.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    temp.replace(target)
