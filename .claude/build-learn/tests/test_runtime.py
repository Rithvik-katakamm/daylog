import concurrent.futures
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runtime import Store, hook, act


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = Store(self.root / 'events.sqlite3')
        self.session = 'test-session'

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def prompt(self, text="I don't understand where this field belongs"):
        hook(self.db, {'hook_event_name': 'UserPromptSubmit',
                      'session_id': self.session, 'prompt': text})
        return self.db.rows('observation')[-1]['id']

    def assess(self, obs, **kwargs):
        body = dict(observation=obs, route='inline', concept='request path',
                    worthy=False, blocking=False, reason='One local clarification',
                    build_issue='CARD-150', evidence=[obs])
        body.update(kwargs)
        return act(self.db, self.session, 'assess', body)

    def test_append_only_and_corrections_preserve_history(self):
        obs = self.prompt()
        first = self.assess(obs)
        second = self.assess(obs, reason='Correction: consequential gap',
                             worthy=True, blocking=True, route='existing', learn_issue='CARD-123')
        self.assertNotEqual(first['id'], second['id'])
        self.assertEqual(len(self.db.rows('assessment')), 2)
        for sql in ['DELETE FROM events', "UPDATE events SET kind='changed'"]:
            with self.assertRaises(sqlite3.IntegrityError):
                self.db.conn.execute(sql)

    def test_signal_is_candidate_not_mastery_and_stops_once(self):
        obs = self.prompt()
        output = hook(self.db, dict(hook_event_name='Stop', session_id=self.session))
        self.assertEqual(output['decision'], 'block')
        self.assertEqual(hook(self.db, dict(hook_event_name='Stop', session_id=self.session,
                                           stop_hook_active=True)), {})
        self.assertEqual(self.db.pending(self.session), [obs])
        self.assess(obs)
        self.assertEqual(self.db.pending(self.session), [])

    def test_factual_question_can_be_dismissed_without_card(self):
        obs = self.prompt('What does HTTP stand for?')
        self.assess(obs, route='none', concept='HTTP acronym', reason='Simple factual answer')
        self.assertFalse(self.db.pending(self.session))
        self.assertEqual(len(self.db.rows('permit')), 0)

    def test_assessment_requires_real_observation_and_nonempty_reason(self):
        with self.assertRaises(ValueError): self.assess(999)
        obs = self.prompt()
        with self.assertRaises(ValueError): self.assess(obs, reason='')
        with self.assertRaises(ValueError): self.assess(obs, route='existing', worthy=True)
        with self.assertRaises(ValueError): self.assess(obs, route='new', worthy=False)

    def test_new_card_requires_search_and_user_request_evidence(self):
        obs = self.prompt()
        with self.assertRaises(ValueError):
            self.assess(obs, route='new', worthy=True)
        request = self.prompt('Please create a learning card for the HTTP boundary')
        search = act(self.db, self.session, 'evidence', dict(kind='search',
                     summary='No existing card covers the boundary', source='linear search HTTP'))['id']
        self.assess(obs, route='new', worthy=True, existing_search=search, user_request=request)

    def test_completion_requires_user_explanation_prediction_and_observed_result(self):
        obs = self.prompt('Cool, got it')
        assessment = self.assess(obs, route='existing', worthy=True, learn_issue='CARD-123')['id']
        tool = 'mcp__linear__update_issue'
        inp = {'id': 'CARD-123', 'state': 'Done'}
        base = dict(tool=tool, tool_input=inp, action='learning_complete',
                    assessment=assessment, reason='Ready', evidence=[obs])
        with self.assertRaises(ValueError): act(self.db, self.session, 'permit', base)
        explanation = self.prompt('The client asks the server; the server reads SQLite')
        prediction = self.prompt('If the server stops, the request should fail')
        result = act(self.db, self.session, 'evidence', dict(kind='verification',
                     summary='Stopped server; request failed as predicted', source='test output local-1'))['id']
        base.update(explanation=explanation, prediction=prediction, verification=result)
        act(self.db, self.session, 'permit', base)
        event = dict(hook_event_name='PreToolUse', session_id=self.session,
                     tool_name=tool, tool_input=inp)
        self.assertEqual(hook(self.db, event), {})
        self.assertEqual(hook(self.db, event)['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_permit_is_bound_to_exact_input_session_and_current_assessment(self):
        obs = self.prompt()
        a = self.assess(obs)['id']
        p = dict(tool='mcp__linear__update_issue', tool_input={'title':'New card','team':'T'},
                 action='build_update', assessment=a, reason='Build is now blocking', evidence=[obs])
        act(self.db, self.session, 'permit', p)
        event = dict(hook_event_name='PreToolUse', session_id='different',
                     tool_name=p['tool'], tool_input=p['tool_input'])
        self.assertEqual(hook(self.db,event)['hookSpecificOutput']['permissionDecision'], 'deny')
        event['session_id'] = self.session
        event['tool_input'] = {'title':'Other card','team':'T'}
        self.assertEqual(hook(self.db,event)['hookSpecificOutput']['permissionDecision'], 'deny')
        event['tool_input'] = p['tool_input']
        self.assess(obs, reason='Changed direction')
        self.assertEqual(hook(self.db,event)['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_cannot_disguise_registered_learn_completion_as_build_update(self):
        obs = self.prompt()
        a = self.assess(obs, route='existing', worthy=True, learn_issue='CARD-123')['id']
        with self.assertRaises(ValueError):
            act(self.db, self.session, 'permit', dict(tool='mcp__linear__update_issue',
                tool_input={'id':'CARD-123','state':'Done'}, action='build_update',
                assessment=a, reason='Shipped', evidence=[obs]))

    def test_user_skip_preserves_unknown_and_feedback_is_direct(self):
        obs = self.prompt()
        self.prompt('/build-learn skip Keep building; revisit later')
        self.assertEqual(self.db.pending(self.session), [])
        self.assertEqual(self.db.rows('override')[-1]['data']['observations'], [obs])
        self.assertEqual(self.db.rows('assessment'), [])
        self.prompt('/build-learn feedback Too many questions')
        self.assertEqual(len(self.db.rows('feedback')), 1)

    def test_restart_recovers_pending_and_does_not_mix_sessions(self):
        obs = self.prompt()
        self.assertEqual(self.db.pending('other-session'), [])
        self.db.close()
        self.db = Store(self.root / 'events.sqlite3')
        start = hook(self.db, dict(hook_event_name='SessionStart', session_id='next'))
        self.assertIn(str(obs), start['hookSpecificOutput']['additionalContext'])

    def test_parallel_appends_are_not_lost(self):
        path = self.root / 'events.sqlite3'
        def append(i):
            db = Store(path)
            try: return db.append('test', 's', {'i':i})
            finally: db.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            ids = list(pool.map(append, range(30)))
        self.assertEqual(len(set(ids)), 30)

    def test_permit_race_only_one_caller_passes(self):
        obs = self.prompt()
        assessment = self.assess(obs)['id']
        tool, inp = 'mcp__linear__update_issue', {'title':'New card','team':'T'}
        act(self.db, self.session, 'permit', dict(tool=tool,tool_input=inp,
             action='build_update',assessment=assessment,reason='Blocks build',evidence=[obs]))
        def attempt(_):
            db = Store(self.root/'events.sqlite3')
            try: return hook(db, dict(hook_event_name='PreToolUse',session_id=self.session,
                                      tool_name=tool,tool_input=inp))
            finally: db.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(attempt,range(4)))
        self.assertEqual(sum(r == {} for r in results),1)

    def test_new_observation_can_supersede_prior_judgment(self):
        obs = self.prompt()
        first = self.assess(obs)['id']
        correction = self.prompt("I understand HTTP; I don't know which running version this is")
        self.assess(correction,concept='running version',supersedes=first)
        self.assertFalse(self.db.current(self.db.get(first)))

    def pre(self, inp, tool='mcp__claude_ai_Linear__save_issue'):
        return hook(self.db, dict(hook_event_name='PreToolUse', session_id=self.session,
                                  tool_name=tool, tool_input=inp))

    def test_pilot_build_card_moves_without_permit(self):
        act(self.db, self.session, 'register', dict(issues=['CARD-123'], source='learn label'))
        self.assertEqual(self.pre({'id':'CARD-150','state':'Done'}), {})
        self.assertEqual(self.pre({'id':'CARD-150','priority':1,'description':'new text'}), {})

    def test_pilot_learn_card_close_and_text_need_permit_but_status_moves_do_not(self):
        act(self.db, self.session, 'register', dict(issues=['card-123'], source='learn label'))
        deny = lambda r: r['hookSpecificOutput']['permissionDecision'] == 'deny'
        self.assertEqual(self.pre({'id':'CARD-123','state':'In Progress'}), {})
        self.assertEqual(self.pre({'id':'CARD-123','priority':2}), {})
        self.assertTrue(deny(self.pre({'id':'CARD-123','state':'Done'})))
        self.assertTrue(deny(self.pre({'id':'CARD-123','description':'rewrite'})))

    def test_pilot_new_card_needs_permit(self):
        r = self.pre({'title':'Anything','team':'T'})
        self.assertEqual(r['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_pilot_detector_skips_plain_how_and_why(self):
        self.prompt('lets look at how we managed that card')
        self.prompt('why not, ship it')
        self.prompt("i don't understand what the ledger stores")
        self.assertEqual([r['data']['candidate'] for r in self.db.rows('observation')],
                         [False, False, True])

    def test_future_schema_is_not_downgraded(self):
        self.db.conn.execute('PRAGMA user_version=99')
        with self.assertRaises(ValueError): Store(self.root/'events.sqlite3')
        self.assertEqual(self.db.conn.execute('PRAGMA user_version').fetchone()[0],99)

    def draft(self):
        obs = self.prompt('How can I know which version I am trying?')
        return act(self.db,self.session,'card_draft',dict(description='A concrete draft for version verification',
            evidence=[obs],experience='Cannot try the change',decision='Which running version to test',
            path='push → CI → release → /health',exercise='Read /health and compare code path',
            prediction='Will a push change a frozen running version?',success='Explain evidence for current version',
            adaptation='Defer depth when in build energy'))['id']

    def review(self, draft, score=2):
        return act(self.db,self.session,'card_review',dict(draft=draft,reviewer='test-critic',
            scores={k:score for k in ['source_fidelity','decision_value','causal_path','independent_check',
                'scope','navigation','adaptation']},vetoes=[],reason='Grounded, focused, and checkable'))['id']

    def test_learning_description_needs_review_for_exact_draft(self):
        draft = self.draft()
        obs = self.db.rows('observation')[-1]['id']
        a = self.assess(obs,worthy=True,route='existing',learn_issue='CARD-123')['id']
        data=dict(tool='mcp__linear__update_issue',tool_input={'id':'CARD-123','description':'A concrete draft for version verification'},
            action='learning_update',assessment=a,reason='Improve the existing card',evidence=[obs])
        with self.assertRaises(ValueError): act(self.db,self.session,'permit',data)
        data['card_review']=self.review(draft)
        act(self.db,self.session,'permit',data)
        data['tool_input']['description']='A different unreviewed card'
        with self.assertRaises(ValueError): act(self.db,self.session,'permit',data)

    def test_low_quality_or_vetoed_card_cannot_be_published(self):
        draft=self.draft()
        obs=self.db.rows('observation')[-1]['id']
        a=self.assess(obs,worthy=True,route='existing',learn_issue='CARD-123')['id']
        data=dict(tool='mcp__linear__update_issue',tool_input={'id':'CARD-123','description':'A concrete draft for version verification'},
            action='learning_update',assessment=a,reason='Revise',evidence=[obs],card_review=self.review(draft,1))
        with self.assertRaises(ValueError): act(self.db,self.session,'permit',data)
        veto=act(self.db,self.session,'card_review',dict(draft=draft,reviewer='critic',
            scores={k:2 for k in ['source_fidelity','decision_value','causal_path','independent_check','scope','navigation','adaptation']},
            vetoes=['Unverified source claim'],reason='Blocked despite score'))['id']
        data['card_review']=veto
        with self.assertRaises(ValueError): act(self.db,self.session,'permit',data)

    def test_card_draft_requires_experience_and_learning_success_condition(self):
        with self.assertRaises(ValueError): act(self.db,self.session,'card_draft',dict(description='Generic CI syllabus'))

    def test_expired_permit_is_denied(self):
        obs=self.prompt()
        a=self.assess(obs)['id']
        tool,inp='mcp__claude_ai_Linear__save_issue',{'title':'New card','team':'T'}
        p=act(self.db,self.session,'permit',dict(tool=tool,tool_input=inp,
            action='build_update',assessment=a,reason='Blocker',evidence=[obs]))['id']
        with patch('runtime.time.time',return_value=self.db.get(p)['at']+601):
            result=hook(self.db,dict(hook_event_name='PreToolUse',session_id=self.session,tool_name=tool,tool_input=inp))
        self.assertEqual(result['hookSpecificOutput']['permissionDecision'],'deny')

    def test_corrupt_ledger_denies_covered_mutation(self):
        script=Path(__file__).resolve().parents[1]/'runtime.py'
        path=self.root/'.learning/build-learn.sqlite3'
        path.parent.mkdir()
        path.write_text('not a database')
        result=subprocess.run([sys.executable,str(script),'--project',str(self.root),'hook'],
            input=json.dumps(dict(hook_event_name='PreToolUse',session_id='x',
                tool_name='mcp__claude_ai_Linear__save_issue',tool_input={'id':'CARD-1'})),
            text=True,capture_output=True)
        self.assertEqual(json.loads(result.stdout)['hookSpecificOutput']['permissionDecision'],'deny')

    def test_input_file_cannot_read_outside_project_ledger_folder(self):
        script=Path(__file__).resolve().parents[1]/'runtime.py'
        source=self.root/'request.json'
        source.write_text('{}')
        result=subprocess.run([sys.executable,str(script),'--project',str(self.root),
            '--input-file',str(source),'assess'],text=True,capture_output=True)
        self.assertEqual(result.returncode,1)
        self.assertIn('inside project .learning',result.stderr)

    def test_cli_protocol_and_read_tools_remain_unblocked(self):
        script = Path(__file__).resolve().parents[1] / 'runtime.py'
        result = subprocess.run([sys.executable, str(script), '--project', str(self.root), 'hook'],
            input=json.dumps(dict(hook_event_name='SessionStart', session_id='real')), text=True,
            capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hookSpecificOutput', json.loads(result.stdout))
        self.assertEqual(hook(self.db, dict(hook_event_name='PreToolUse', session_id='x',
            tool_name='mcp__linear__get_issue',tool_input={'id':'CARD-1'})), {})


if __name__ == '__main__': unittest.main()
