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
        queues = candidate_queues(self.named_queues, 'ovhca1-47', False)

        self.assertEqual(['pending:ovhca1-47', 'pending-ao', 'pending'], queues)

    def test_selects_substring_match_on_nick(self):
        queues = candidate_queues(self.named_queues, 'ovhca1-reddit-over18-55', False)

        self.assertEqual(['pending:reddit-over18', 'pending-ao', 'pending'], queues)

    def test_only_checks_pending_ao_if_ao_only(self):
        queues = candidate_queues(self.named_queues, 'ovhca1-reddit-over18-55', True)

        self.assertEqual(['pending-ao'], queues)
