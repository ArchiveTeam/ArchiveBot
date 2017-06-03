import json
import re
from glob import glob

import pytest

ignore_pattern_files = glob('db/ignore_patterns/*.json')
user_agent_files = glob('db/user_agents/*.json')

@pytest.mark.parametrize('filename', ignore_pattern_files)
def test_ignore_pattern_file(filename):
    data = json.load(open(filename))
    assert data['type'] == 'ignore_patterns'
    assert data['name']
    assert type(data['patterns']) == list
    
    for pattern in data['patterns']:
        re.compile(pattern)

@pytest.mark.parametrize('filename', user_agent_files)
def test_user_agent_file(filename):
    data = json.load(open(filename))
    assert data['type'] == 'user_agents'
    assert type(data['agents']) == list
    
    for agent in data['agents']:
        assert len(agent['aliases']) > 0
        assert agent['name']
    

