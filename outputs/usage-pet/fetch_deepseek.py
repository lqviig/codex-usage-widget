"""Read today's DeepSeek platform spend and token usage.

The figures come from the platform dashboard endpoints. Set DEEPSEEK_USER_TOKEN
to a valid platform token before starting the widget. This module never reads
browser profiles, browser caches, or stored credentials.
"""
import datetime
import json
import os
import pathlib
import ssl
import sys
import time
import urllib.error
import urllib.request

PLATFORM = 'https://platform.deepseek.com'
BEIJING = datetime.timezone(datetime.timedelta(hours=8))
# DeepSeek bills an input token as either a cache hit or a miss; older models
# report one flat prompt counter instead, handled in today_figures().
TOKEN_KINDS = ('PROMPT_CACHE_HIT_TOKEN', 'PROMPT_CACHE_MISS_TOKEN', 'RESPONSE_TOKEN')
CONTEXT = ssl.create_default_context()


def request_json(url, token):
    request = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/json',
        'x-app-version': '1.0.0',
        'User-Agent': 'Mozilla/5.0',
    })
    with urllib.request.urlopen(request, timeout=20, context=CONTEXT) as response:
        return json.loads(response.read().decode('utf-8'))


def token_accepted(token):
    try:
        payload = request_json(PLATFORM + '/api/v0/users/get_user_summary', token)
    except Exception:
        return False
    return payload.get('code') == 0


def session_token():
    token = os.environ.get('DEEPSEEK_USER_TOKEN', '').strip()
    if not token:
        raise RuntimeError('请设置 DEEPSEEK_USER_TOKEN 后重新刷新')
    if token_accepted(token):
        return token
    raise RuntimeError('DeepSeek 登录令牌无效或已过期')


def pick_block(payload):
    block = (payload.get('data') or {}).get('biz_data')
    if isinstance(block, list):
        for element in block:
            if isinstance(element, dict) and 'days' in element:
                return element
        return block[0] if block else {}
    return block or {}


def today_figures(cost_block, amount_block, day):
    spend = 0.0
    cost_day = next((item for item in cost_block.get('days') or [] if item.get('date') == day), None)
    for model in (cost_day or {}).get('data') or []:
        for entry in model.get('usage') or []:
            spend += float(entry.get('amount') or 0)

    tokens = requests = flat_prompt = 0
    amount_day = next((item for item in amount_block.get('days') or [] if item.get('date') == day), None)
    for model in (amount_day or {}).get('data') or []:
        counts = {}
        for entry in model.get('usage') or []:
            counts[entry.get('type')] = int(float(entry.get('amount') or 0))
        tokens += sum(counts.get(kind, 0) for kind in TOKEN_KINDS)
        flat_prompt += counts.get('PROMPT_TOKEN', 0)
        requests += counts.get('REQUEST', 0)
    if tokens == 0:
        tokens = flat_prompt
    return {
        'cost': round(spend, 6),
        'tokens': tokens,
        'requests': requests,
        'currency': cost_block.get('currency') or 'CNY',
    }


def month_usage(token, now):
    query = f'month={now.month}&year={now.year}'
    cost = pick_block(request_json(f'{PLATFORM}/api/v0/usage/cost?{query}', token))
    amount = pick_block(request_json(f'{PLATFORM}/api/v0/usage/amount?{query}', token))
    return cost, amount


def main():
    target = pathlib.Path(sys.argv[1])
    now = datetime.datetime.now(BEIJING)
    try:
        token = session_token()
        cost_block, amount_block = month_usage(token, now)
        data = {'ok': True, 'at': time.time(), 'date': now.date().isoformat()}
        data.update(today_figures(cost_block, amount_block, now.date().isoformat()))
    except Exception as error:
        message = str(error) or error.__class__.__name__
        data = {'ok': False, 'at': time.time(), 'error': message}
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    temporary.replace(target)


if __name__ == '__main__':
    main()
