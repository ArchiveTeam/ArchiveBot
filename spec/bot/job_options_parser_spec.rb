require 'spec_helper'

require 'bot/job_options_parser'

describe JobOptionsParser do
  let(:parser) { JobOptionsParser.new }

  it 'recognizes --no-offsite-links' do
    expect(parser.parse('--no-offsite-links')[:no_offsite_links]).to eq(true)
  end

  it 'recognizes alias --nooffsite' do
    expect(parser.parse('--nooffsite')[:no_offsite_links]).to eq(true)
  end

  it 'parses --ignore-sets=A,B to an array' do
    expect(parser.parse('--ignore-sets=A,B')[:ignore_sets]).to eq(['A', 'B'])
  end

  it 'parses alias --ignoreset=A,B to an array' do
    expect(parser.parse('--ignoreset=A,B')[:ignore_sets]).to eq(['A', 'B'])
  end

  it 'recognizes --pipeline=ID' do
    expect(parser.parse('--pipeline=ID')[:pipeline]).to eq('ID')
  end

  it 'recognizes --user-agent-alias=firefox' do
    expect(parser.parse('--user-agent-alias=firefox')[:user_agent_alias]).to eq('firefox')
  end

  it 'recognizes alias --user-agent=firefox' do
    expect(parser.parse('--user-agent=firefox')[:user_agent_alias]).to eq('firefox')
  end

  it 'recognizes --youtube-dl' do
    expect(parser.parse('--youtube-dl')[:youtube_dl]).to eq(true)
  end

  it 'recognizes --explain=Stuff' do
    expect(parser.parse('--explain=Stuff')[:explain]).to eq('Stuff')
  end

  it 'recognizes --explain="Double quoted stuff with spaces"' do
    expect(parser.parse('--explain="Double quoted stuff with spaces"')[:explain]).to eq('Double quoted stuff with spaces')
  end

  it 'parses --delay=12 to an integer' do
    expect(parser.parse('--delay=12')[:delay]).to eq(12)
  end

  it 'parses --concurrency=4 to an integer' do
    expect(parser.parse('--concurrency=4')[:concurrency]).to eq(4)
  end

  it 'recognizes --no-cookies' do
    expect(parser.parse('--no-cookies')[:no_cookies]).to eq(true)
  end

  describe 'when unknown options are present' do
    it 'raises UnknownOptionError' do
      expect(lambda { parser.parse('--foo=bar') }).to raise_error(JobOptionsParser::UnknownOptionError)
    end

    it 'returns the unknown option in the exception message' do
      begin
        parser.parse('--foo=bar')
      rescue JobOptionsParser::UnknownOptionError => e
        ex = e
      end

      expect(ex.message).to match(/--foo/)
    end
  end
end
