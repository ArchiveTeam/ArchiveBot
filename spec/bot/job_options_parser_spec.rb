require 'spec_helper'

require 'bot/job_options_parser'

describe JobOptionsParser do
  let(:parser) { JobOptionsParser.new }

  it 'recognizes --phantomjs' do
    parser.parse('--phantomjs')[:phantomjs].should eq(true)
  end

  it 'parses --phantomjs-scroll=10 to an integer' do
    parser.parse('--phantomjs-scroll=10')[:phantomjs_scroll].should == 10
  end

  it 'parses --phantomjs-wait=4.25 to a float' do
    parser.parse('--phantomjs-wait=4.25')[:phantomjs_wait].should == 4.25
  end

  it 'recognizes --no-phantomjs-smart-scroll' do
    parser.parse('--no-phantomjs-smart-scroll')[:no_phantomjs_smart_scroll].should eq(true)
  end

  it 'recognizes --no-offsite-links' do
    parser.parse('--no-offsite-links')[:no_offsite_links].should eq(true)
  end

  it 'recognizes alias --nooffsite' do
    parser.parse('--nooffsite')[:no_offsite_links].should eq(true)
  end

  it 'parses --ignore-sets=A,B to an array' do
    parser.parse('--ignore-sets=A,B')[:ignore_sets].should == ['A', 'B']
  end

  it 'parses alias --ignoreset=A,B to an array' do
    parser.parse('--ignoreset=A,B')[:ignore_sets].should == ['A', 'B']
  end

  it 'recognizes --pipeline=ID' do
    parser.parse('--pipeline=ID')[:pipeline].should == 'ID'
  end

  it 'recognizes --user-agent-alias=firefox' do
    parser.parse('--user-agent-alias=firefox')[:user_agent_alias].should == 'firefox'
  end

  it 'recognizes alias --user-agent=firefox' do
    parser.parse('--user-agent=firefox')[:user_agent_alias].should == 'firefox'
  end

  it 'recognizes --youtube-dl' do
    parser.parse('--youtube-dl')[:youtube_dl].should eq(true)
  end

  it 'recognizes --explain=Stuff' do
    parser.parse('--explain=Stuff')[:explain].should == 'Stuff'
  end

  it 'recognizes --explain="Double quoted stuff with spaces"' do
    parser.parse('--explain="Double quoted stuff with spaces"')[:explain].should == 'Double quoted stuff with spaces'
  end

  it 'parses --delay=12 to an integer' do
    parser.parse('--delay=12')[:delay].should == 12
  end

  it 'parses --concurrency=4 to an integer' do
    parser.parse('--concurrency=4')[:concurrency].should == 4
  end

  describe 'when unknown options are present' do
    it 'raises UnknownOptionError' do
      lambda { parser.parse('--foo=bar') }.should raise_error(JobOptionsParser::UnknownOptionError)
    end

    it 'returns the unknown option in the exception message' do
      begin
        parser.parse('--foo=bar')
      rescue JobOptionsParser::UnknownOptionError => e
        ex = e
      end

      ex.message.should =~ /--foo/
    end
  end
end
