import unittest

from .control import candidate_queues

class TestCandidateQueues(unittest.TestCase):
    def setUp(self):
        self.named_queues = set([
            'pending:internetcentrum',
            'pending:reddit-over18',
            'pending:ovhca1-47'
        ])

    def test_selects_exact_match_on_nick(self):
        queues = candidate_queues(self.named_queues, 'ovhca1-47', False, large=False)

        self.assertEqual(set(['pending:ovhca1-47', 'pending-ao', 'pending']), set(queues))

    def test_selects_substring_match_on_nick(self):
        queues = candidate_queues(self.named_queues, 'ovhca1-reddit-over18-55', False, large=False)

        self.assertEqual(set(['pending:reddit-over18', 'pending-ao', 'pending']), set(queues))

    def test_only_checks_pending_ao_if_ao_only(self):
        queues = candidate_queues(self.named_queues, 'ovhca1-reddit-over18-55', True, large=False)

        self.assertEqual(set(['pending-ao']), set(queues))
