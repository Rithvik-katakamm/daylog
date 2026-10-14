#!/usr/bin/env python3
"""Build/learn v0.1: local evidence ledger and narrow Claude Code action gates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import time

VERSION = '0.1.0-daylog'
POLICY = 'adaptive-v1-daylog'
# Day Log pilot: the phrase list from the old learn-trigger hook. The plugin's bare "how"/"why"
# flagged 61% of his prompts (vs 51%), and every flag costs a recorded assessment before Stop.
SIGNAL = re.compile(
    r"\b(i\s*don'?t\s+(get|understand|know\s+(what|how|why))|what('?s| is| are| does| do)\b|"
    r"why\s+(does|is|do|did|are|would)|how\s+(does|do|is)|explain|confus|lost\s+me|huh\b|wtf|"
    r"no\s+idea|teach\s+me|what\s+do\s+you\s+mean|eli5|i'?m\s+lost)", re.I)
MUTATION = re.compile(r'linear.*(?:create|update|save)_issue$', re.I)
HOOK_MATCHER = 'mcp__.*[Ll][Ii][Nn][Ee][Aa][Rr].*__(create|update|save)_issue'
ROUTES = {'none', 'inline', 'existing', 'new', 'deferred'}
ACTIVE_STATES = {'backlog','todo','in progress','triage','started','canceled','cancelled'}
CARD_DIMENSIONS = {'source_fidelity','decision_value','causal_path','independent_check','scope','navigation','adaptation'}


def packed(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def fingerprint(tool, inp):
    return hashlib.sha256(packed([tool, inp]).encode()).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def words(value):
    return isinstance(value, str) and bool(value.strip())


class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.conn = sqlite3.connect(str(self.path), timeout=2, isolation_level=None)
        os.chmod(self.path, 0o600)
        self.conn.row_factory = sqlite3.Row
        schema = self.conn.execute('PRAGMA user_version').fetchone()[0]
        if schema > 1:
            self.conn.close()
            raise ValueError('Ledger schema is newer than this runtime; refusing to downgrade')
        self.conn.execute('PRAGMA journal_mode=WAL')
        self.conn.executescript('''
          CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY, at REAL NOT NULL, kind TEXT NOT NULL,
            session TEXT NOT NULL, policy TEXT NOT NULL, data TEXT NOT NULL);
          CREATE INDEX IF NOT EXISTS by_kind_session ON events(kind,session,id);
          CREATE TRIGGER IF NOT EXISTS no_update BEFORE UPDATE ON events
            BEGIN SELECT RAISE(ABORT,'append only'); END;
          CREATE TRIGGER IF NOT EXISTS no_delete BEFORE DELETE ON events
            BEGIN SELECT RAISE(ABORT,'append only'); END;
          PRAGMA user_version=1;
        ''')

    def close(self):
        self.conn.close()

    def append(self, kind, session, data):
        cur = self.conn.execute('INSERT INTO events(at,kind,session,policy,data) VALUES(?,?,?,?,?)',
                                (time.time(), kind, session, POLICY, packed(data)))
        return cur.lastrowid

    def rows(self, kind=None, session=None):
        where, args = [], []
        if kind is not None: where.append('kind=?'); args.append(kind)
        if session is not None: where.append('session=?'); args.append(session)
        sql = 'SELECT * FROM events' + (' WHERE ' + ' AND '.join(where) if where else '') + ' ORDER BY id'
        return [dict(row, data=json.loads(row['data'])) for row in self.conn.execute(sql, args)]

    def get(self, ident, kinds=None):
        need(type(ident) is int, 'Evidence/assessment IDs must be integers')
        row = self.conn.execute('SELECT * FROM events WHERE id=?', (ident,)).fetchone()
        need(row is not None, 'Unknown evidence ID: %s' % ident)
        item = dict(row, data=json.loads(row['data']))
        need(kinds is None or item['kind'] in kinds, 'Wrong evidence kind for ID %s' % ident)
        return item

    def pending(self, session=None):
        resolved = {r['data']['observation'] for r in self.rows('assessment')}
        resolved.update(i for r in self.rows('override') for i in r['data']['observations'])
        return [r['id'] for r in self.rows('observation', session)
                if r['data']['candidate'] and r['id'] not in resolved]

    def learn_cards(self):
        """Learn cards the gate protects: registered ones plus any an assessment linked."""
        cards = {str(r['data'].get('learn_issue')).upper() for r in self.rows('assessment')
                 if r['data'].get('learn_issue')}
        cards.update(str(i).upper() for r in self.rows('learn_card') for i in r['data']['issues'])
        return cards

    def needs_permit(self, inp):
        """Day Log pilot: build cards move freely. Gate only a new card, and a learn card's
        content (description) or close (any state outside ACTIVE_STATES)."""
        if not isinstance(inp, dict):
            return True
        target = str(inp.get('id') or inp.get('issueId') or '').upper()
        if not target:
            return True
        if target not in self.learn_cards():
            return False
        if 'description' in inp:
            return True
        state = inp.get('state', inp.get('status'))
        return state is not None and str(state).lower() not in ACTIVE_STATES

    def current(self, assessment):
        observation = assessment['data']['observation']
        return not any(r['id'] > assessment['id'] and (r['data']['observation'] == observation
                       or r['data'].get('supersedes') == assessment['id'])
                       for r in self.rows('assessment'))


def act(db, session, action, data):
    """Host-model assessments remain explicitly labeled judgments, never ground truth."""
    with db.conn:
        if action == 'assess':
            db.get(data.get('observation'), {'observation'})
            if data.get('supersedes') is not None:
                db.get(data['supersedes'], {'assessment'})
            need(data.get('route') in ROUTES, 'Unknown route')
            for field in ('concept', 'reason', 'build_issue'):
                need(words(data.get(field)), '%s is required (use unassigned for no issue)' % field)
            for field in ('worthy', 'blocking'):
                need(type(data.get(field)) is bool, '%s must be boolean' % field)
            need(isinstance(data.get('evidence'), list) and data['evidence'], 'Cite evidence IDs')
            for ident in data['evidence']: db.get(ident, {'observation','evidence','feedback'})
            if data['route'] in {'existing', 'new', 'deferred'}:
                need(data['worthy'], 'Durable learning requires worthiness rationale')
            if data['route'] == 'existing':
                need(words(data.get('learn_issue')), 'Existing route requires learn_issue')
            if data['route'] == 'new':
                search = db.get(data.get('existing_search'), {'evidence'})
                need(search['data']['kind'] == 'search', 'Search existing issues before new card')
                db.get(data.get('user_request'), {'observation'})
            ident=db.append('assessment', session, dict(data, origin='model_judgment'))
            return {'id':ident,'observation_assessed':data['observation'],
                    'pending_in_session':db.pending(session),
                    'note':'Assessment resolves triage, not learning completion.'}
        if action == 'evidence':
            need(data.get('kind') in {'verification','search','code','shipping','decision_result'}, 'Unknown evidence kind')
            need(words(data.get('summary')) and words(data.get('source')), 'Evidence requires summary and source')
            return {'id': db.append('evidence', session, dict(data, origin='agent_recorded_source'))}
        if action == 'outcome':
            db.get(data.get('assessment'), {'assessment'})
            need(data.get('result') in {'helped','hurt','unclear'}, 'Outcome: helped, hurt, unclear')
            need(words(data.get('reason')), 'Outcome requires a reason')
            need(data.get('evidence'), 'Outcome requires evidence, not a success guess')
            for ident in data['evidence']: db.get(ident, {'observation','evidence','feedback'})
            return {'id': db.append('outcome', session, dict(data, origin='model_judgment'))}
        if action == 'card_draft':
            for field in ('description','experience','decision','path','exercise','prediction','success','adaptation'):
                need(words(data.get(field)), 'Card draft requires '+field)
            need(data.get('evidence'), 'Card draft requires source evidence')
            for ident in data['evidence']: db.get(ident, {'observation','evidence','feedback'})
            return {'id':db.append('card_draft',session,dict(data,
                content_hash=hashlib.sha256(data['description'].encode()).hexdigest(),origin='model_authored'))}
        if action == 'card_review':
            db.get(data.get('draft'),{'card_draft'})
            need(words(data.get('reviewer')) and words(data.get('reason')), 'Review requires reviewer and rationale')
            scores=data.get('scores',{})
            need(set(scores)==CARD_DIMENSIONS, 'Review all seven card dimensions')
            need(all(type(v) is int and 0<=v<=2 for v in scores.values()), 'Scores must be integers 0..2')
            need(isinstance(data.get('vetoes'),list) and all(words(v) for v in data['vetoes']), 'Provide vetoes list')
            return {'id':db.append('card_review',session,dict(data,origin='model_judgment',
                passed=not data['vetoes'] and min(scores.values())>=1 and sum(scores.values())>=12))}
        if action == 'permit':
            assessment = db.get(data.get('assessment'), {'assessment'})
            need(db.current(assessment), 'Assessment superseded; use the latest revision')
            need(assessment['session'] == session, 'Record an assessment in this session before mutation')
            need(words(data.get('reason')) and data.get('evidence'), 'Mutation needs rationale and evidence')
            for ident in data['evidence']: db.get(ident, {'observation','evidence','feedback'})
            tool, inp = data.get('tool', ''), data.get('tool_input')
            need(MUTATION.search(tool) and isinstance(inp, dict), 'Supported Linear issue tool and exact input required')
            mode = data.get('action')
            need(mode in {'build_update','learning_create','learning_update','learning_complete','reorder'}, 'Unknown action')
            target = str(inp.get('id', inp.get('issueId', '')))
            is_learning = target.upper() in db.learn_cards() or target == assessment['data'].get('learn_issue')
            if is_learning:
                need(mode in {'learning_update','learning_complete','reorder'}, 'Registered learning card cannot be a build update')
            state = inp.get('state', inp.get('status'))
            if state is not None and is_learning:
                # Treat unknown status UUIDs as a possible completion; conservative by design.
                if str(state).lower() not in ACTIVE_STATES:
                    need(mode == 'learning_complete', 'Potential learning completion requires completion evidence')
            if mode == 'learning_create':
                need(assessment['data']['route'] == 'new', 'New card requires assessed new route')
            if mode == 'learning_create' or (mode == 'learning_update' and 'description' in inp):
                review=db.get(data.get('card_review'),{'card_review'})
                need(review['data']['passed'], 'Card review has a veto or falls below the v1 review threshold')
                draft=db.get(review['data']['draft'],{'card_draft'})
                need(inp.get('description')==draft['data']['description'], 'Only the exact reviewed description can be published')
            if mode == 'learning_complete':
                need(is_learning, 'Link learn_issue in the assessment first')
                db.get(data.get('explanation'), {'observation'})
                db.get(data.get('prediction'), {'observation'})
                check = db.get(data.get('verification'), {'evidence'})
                need(check['data']['kind'] == 'verification', 'Shipping is not verification of learning')
            if mode == 'reorder':
                need(words(data.get('ranking_change')), 'Describe previous → next ordering and why')
            return {'id': db.append('permit', session, dict(data, fingerprint=fingerprint(tool, inp)))}
        if action == 'register':
            issues = data.get('issues')
            need(isinstance(issues, list) and issues and all(words(i) for i in issues), 'List learn card IDs')
            need(words(data.get('source')), 'Say where the list came from')
            return {'id': db.append('learn_card', session, dict(data, origin='agent_recorded_source'))}
        raise ValueError('Unknown action')


def context(event, text):
    return {'hookSpecificOutput': {'hookEventName': event, 'additionalContext': text}}


def hook(db, payload):
    event = payload.get('hook_event_name')
    session = payload.get('session_id', 'unknown')
    with db.conn:
        if event == 'SessionStart':
            plugin = os.environ.get('CLAUDE_PLUGIN_ROOT')
            skill = str(Path(plugin)/'skills/build-learn/SKILL.md') if plugin else '.claude/skills/build-learn/SKILL.md'
            runtime = str(Path(plugin)/'runtime.py') if plugin else '.claude/build-learn/runtime.py'
            return context(event, 'Build/learn v%s active. Read %s. '
                'CLI: python3 %s --session %s status. Use this runtime path for all '
                'commands in the skill reference. Pending observation IDs across sessions: %s. '
                'These are questions to assess, not evidence of incompetence. Keep real build work first.'
                % (VERSION, skill, json.dumps(runtime), session, db.pending()[-20:]))
        if event == 'UserPromptSubmit':
            prompt = payload.get('prompt', '')
            candidate = bool(SIGNAL.search(prompt))
            ident = db.append('observation', session, dict(text=prompt[:2000],
                truncated=len(prompt)>2000, transcript=payload.get('transcript_path'),
                candidate=candidate, origin='user_prompt'))
            skip = re.match(r'^/?build-learn skip\s+(.+)', prompt, re.I | re.S)
            feedback = re.match(r'^/?build-learn feedback\s+(.+)', prompt, re.I | re.S)
            if skip:
                db.append('override', session, dict(observations=db.pending(session),
                          reason=skip.group(1)[:2000], source=ident, origin='user_prompt'))
                return context(event, 'User chose to skip learning checks for current pending questions. '
                               'Continue building; understanding remains unverified. Override recorded.')
            if feedback:
                db.append('feedback', session, dict(text=feedback.group(1)[:2000], source=ident,
                          origin='user_prompt'))
                # Feedback may itself contain a candidate: still assess the correction.
            if candidate or feedback:
                return context(event, 'Build/learn observation %s (candidate only). Use build-learn skill: '
                    'assess current consequence, worthiness, timing, existing card; record rationale. '
                    'Simple questions may get a direct answer and route none/inline. Do not infer mastery '
                    'from code you wrote. User feedback changes the next decision.' % ident)
            return {}
        if event == 'Stop':
            pending = db.pending(session)
            if pending and not payload.get('stop_hook_active'):
                db.append('intervention', session, dict(observations=pending, reason='unassessed'))
                return {'decision':'block', 'reason':'Record a brief build-learn assessment for observations '
                        '%s before finishing (none/inline is valid; do not force a lesson). Read the skill.' % pending}
            return {}
        if event == 'PreToolUse' and MUTATION.search(payload.get('tool_name', '')):
            if not db.needs_permit(payload.get('tool_input', {})):
                return {}  # a build card's status, priority or text: no permit
            fp = fingerprint(payload['tool_name'], payload.get('tool_input', {}))
            # SQLite's writer lock makes one-shot permit consumption atomic across hooks.
            db.conn.execute('BEGIN IMMEDIATE')
            used = {r['data']['permit'] for r in db.rows('consumed')}
            permits = [r for r in db.rows('permit', session) if r['id'] not in used
                       and r['data']['fingerprint'] == fp and time.time()-r['at'] <= 600
                       and db.current(db.get(r['data']['assessment'], {'assessment'}))]
            if permits:
                db.append('consumed', session, dict(permit=permits[-1]['id'],
                    tool_use_id=payload.get('tool_use_id'), fingerprint=fp))
                return {}  # Never override the user's ordinary tool permissions.
            return {'hookSpecificOutput': {'hookEventName': event, 'permissionDecision':'deny',
                'permissionDecisionReason':'Build/learn requires a one-use permit for this exact Linear '
                'write (a new card, or a learn card’s text or close). Record assessment and permit through runtime.py. No new user approval '
                'needed for already-authorized work. See skill reference.'}}
        if event == 'PostToolUse' and MUTATION.search(payload.get('tool_name', '')):
            db.append('tool_result', session, dict(tool=payload['tool_name'],
                tool_use_id=payload.get('tool_use_id'),
                fingerprint=fingerprint(payload['tool_name'], payload.get('tool_input', {})),
                is_error=bool(payload.get('tool_response', {}).get('isError'))
                if isinstance(payload.get('tool_response'),dict) else None,
                origin='observed_tool_return'))
            return {}
        return {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', default=os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd()))
    parser.add_argument('--session', default='manual')
    parser.add_argument('--input-file', help='Read action JSON from a file inside project .learning/')
    parser.add_argument('--data-json', help='Action JSON as one shell-quoted argument, without redirection')
    parser.add_argument('command', choices=['hook','status','export','assess','evidence','permit','outcome','card_draft','card_review','register'])
    args = parser.parse_args()
    project = Path(args.project).resolve()
    db = None
    payload = {}
    try:
        need(not (args.input_file and args.data_json), 'Use only one JSON input mechanism')
        if args.data_json:
            need(args.command not in {'hook','status','export'}, 'data-json is for recorded actions only')
            payload = json.loads(args.data_json)
        elif args.input_file:
            path = Path(args.input_file).resolve()
            need(args.command not in {'hook','status','export'}, 'input-file is for recorded actions only')
            need((project / '.learning').resolve() in path.parents, 'Input file must be inside project .learning/')
            payload = json.loads(path.read_text())
        elif args.command not in {'status','export'}:
            payload = json.load(sys.stdin)
        need(isinstance(payload,dict), 'JSON input must be an object')
        db = Store(project / '.learning' / 'build-learn.sqlite3')
        if args.command == 'hook': result = hook(db, payload)
        elif args.command == 'status':
            result = dict(version=VERSION, policy=POLICY, pending=db.pending(),
                assessments=[r for r in db.rows('assessment') if db.current(r)][-8:], feedback=db.rows('feedback')[-5:],
                outcomes=db.rows('outcome')[-5:], learn_cards=sorted(db.learn_cards()))
        elif args.command == 'export': result = db.rows()
        else: result = act(db, args.session, args.command, payload)
        print(json.dumps(result, ensure_ascii=False))
    except (ValueError, sqlite3.Error, OSError) as exc:
        if args.command == 'hook':
            event = payload.get('hook_event_name')
            if event == 'PreToolUse' and MUTATION.search(payload.get('tool_name','')):
                print(json.dumps({'hookSpecificOutput': {'hookEventName': event,
                    'permissionDecision':'deny', 'permissionDecisionReason':'Build/learn ledger unavailable: '+str(exc)}}))
            else:
                print(json.dumps({'systemMessage':'Build/learn recording unavailable: '+str(exc)}))
        else:
            print(str(exc), file=sys.stderr)
            return 1
    finally:
        if db: db.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
